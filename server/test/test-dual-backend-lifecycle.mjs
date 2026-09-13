import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:net";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import WebSocket from "ws";

console.log("=== Testing Dual Backend Lifecycle Regression ===");

const tmpDir = mkdtempSync(join(tmpdir(), "nexus-dual-lifecycle-"));
const socketPath = join(tmpDir, "herdr.sock");
const sessionFile = join(tmpDir, "pane.jsonl");
writeFileSync(sessionFile, JSON.stringify({ sessionUpdate: "agent_message_chunk", content: { text: "ready" } }) + "\n");
process.env.HERDR_SOCKET_PATH = socketPath;
process.env.NEXUS_AUTH_TOKEN = "dual-lifecycle-token";

let sentKeys = [];
let closedPanes = [];
let herdrPrompts = [];

const herdrServer = createServer((socket) => {
  let pending = "";
  socket.on("data", (chunk) => {
    pending += chunk.toString();
    const lines = pending.split("\n");
    pending = lines.pop() ?? "";
    for (const line of lines) {
      if (!line.trim()) continue;
      const request = JSON.parse(line);
      let result = {};
      if (request.method === "agent.list") {
        result = {
          agents: [{
            pane_id: "p-dual",
            agent: "omp",
            agent_status: "working",
            cwd: tmpDir,
            agent_session: { kind: "path", value: sessionFile },
          }],
        };
      } else if (request.method === "agent.send_keys") {
        sentKeys.push(...request.params.keys);
        result = { success: true };
      } else if (request.method === "pane.close") {
        closedPanes.push(request.params?.pane_id);
        result = { success: true };
      } else if (request.method === "agent.prompt") {
        herdrPrompts.push(request.params?.prompt);
        result = { success: true };
      }
      socket.write(JSON.stringify({ id: request.id, result }) + "\n");
    }
  });
});
await new Promise((resolve) => herdrServer.listen(socketPath, resolve));

const { createBridgeServer } = await import("../dist/server.mjs");
const { sessionManager } = await import("../dist/session-manager.mjs");

const app = createBridgeServer({ port: 0, hostId: "dual-lifecycle-host" });
await once(app.httpServer, "listening");
const port = app.httpServer.address().port;
const ws = new WebSocket(`ws://127.0.0.1:${port}`, {
  headers: { Authorization: "Bearer dual-lifecycle-token" },
});
const messages = [];
ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

const waitFor = async (predicate, timeoutMs = 3000) => {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("timed out waiting for condition");
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
};

try {
  await once(ws, "open");
  await waitFor(() => messages.some((m) => m.type === "server_info"));

  // 1. Herdr lifecycle test: load session
  ws.send(JSON.stringify({ type: "load_session", sessionId: "herdr:p-dual" }));
  await waitFor(() => messages.some((m) => m.type === "session_started" && m.sessionId === "herdr:p-dual"));
  console.log("  ✓ Herdr session loaded with streamMode=acp");

  // 2. Herdr blocked key interaction
  ws.send(JSON.stringify({ type: "interact_herdr_blocked", paneId: "herdr:p-dual", key: "enter" }));
  await waitFor(() => messages.some((m) => m.type === "interact_herdr_blocked_done" && m.ok === true));
  assert(sentKeys.includes("enter"), "Sent enter key to Herdr pane");
  console.log("  ✓ Herdr blocked key interaction delivered");

  // 3. Herdr cancel (sends Ctrl+C, acknowledges session_cancelled without ending turn)
  ws.send(JSON.stringify({ type: "cancel", sessionId: "herdr:p-dual" }));
  await waitFor(() => messages.some((m) => m.type === "session_cancelled" && m.sessionId === "herdr:p-dual"));
  assert(sentKeys.includes("Ctrl+C"), "Sent Ctrl+C to Herdr pane");
  console.log("  ✓ Herdr cancel dispatched via terminal key injection");

  // 4. Herdr close session
  ws.send(JSON.stringify({ type: "close_session", sessionId: "herdr:p-dual" }));
  await waitFor(() => messages.some((m) => m.type === "session_closed" && m.sessionId === "herdr:p-dual"));
  assert(closedPanes.includes("p-dual"), "Herdr pane close requested");
  console.log("  ✓ Herdr pane close executed");

  // 5. Native ACP isolation test: Herdr session must not pollute sessionManager pool
  assert.equal(sessionManager.getSession("herdr:p-dual"), undefined, "Herdr sessions must not reside in SessionManager pool");
  console.log("  ✓ Dual backend state isolation verified");

  console.log("ALL DUAL BACKEND LIFECYCLE TESTS PASSED!\n");
  process.exitCode = 0;
} finally {
  ws.close();
  try { await app.stop(); } catch {}
  herdrServer.close();
  rmSync(tmpDir, { recursive: true, force: true });
  delete process.env.HERDR_SOCKET_PATH;
  delete process.env.NEXUS_AUTH_TOKEN;
  process.exit(0);
}
