import assert from "node:assert/strict";
import { once } from "node:events";
import { createServer } from "node:net";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import WebSocket from "ws";

const tmpDir = mkdtempSync(join(tmpdir(), "nexus-herdr-ops-"));
const socketPath = join(tmpDir, "herdr.sock");
const sessionFile = join(tmpDir, "session-id.jsonl");
writeFileSync(sessionFile, "");
process.env.HERDR_SOCKET_PATH = socketPath;
process.env.NEXUS_AUTH_TOKEN = "herdr-ops-token";

let closedPane = "";
let agentStatus = "working";
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
            pane_id: "sync-pane",
            agent: "omp",
            agent_status: agentStatus,
            cwd: tmpDir,
            agent_session: { kind: "path", value: sessionFile },
          }],
        };
      } else if (request.method === "pane.close") {
        closedPane = request.params?.pane_id ?? "";
      }
      socket.write(JSON.stringify({ id: request.id, result }) + "\n");
    }
  });
});
await new Promise((resolve) => herdrServer.listen(socketPath, resolve));

const { createBridgeServer } = await import("../dist/server.mjs");
const { HerdrAdapter } = await import("../dist/discovery/herdr-adapter.mjs");
const { handleCancel } = await import("../dist/handlers/cancel.mjs");
const { HerdrTailerRegistry } = await import("../dist/discovery/herdr-session-tailer.mjs");

const waitFor = async (predicate, timeoutMs = 3000) => {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("timed out waiting for condition");
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
};

const app = createBridgeServer({ port: 0, hostId: "herdr-ops-host" });
await once(app.httpServer, "listening");
const port = app.httpServer.address().port;
const ws = new WebSocket(`ws://127.0.0.1:${port}`, {
  headers: { Authorization: "Bearer herdr-ops-token" },
});
const messages = [];
ws.on("message", (raw) => messages.push(JSON.parse(raw.toString())));

try {
  await once(ws, "open");
  await waitFor(() => messages.some((message) => message.type === "server_info"));

  ws.send(JSON.stringify({ type: "sync_request", sessionId: "herdr:sync-pane" }));
  await waitFor(() => messages.some((message) =>
    message.type === "session_started" && message.sessionId === "herdr:sync-pane"));
  assert(HerdrTailerRegistry.get("herdr:sync-pane"), "sync_request must restore the Herdr tailer subscription");
  assert(!messages.some((message) => message.code === "SESSION_NOT_FOUND"), "Herdr sync must bypass SessionManager ownership");

  const originalSendKeys = HerdrAdapter.sendKeys;
  let releaseSendKeys;
  HerdrAdapter.sendKeys = () => new Promise((resolve) => { releaseSendKeys = resolve; });
  const cancelMessages = [];
  handleCancel({ send: (raw) => cancelMessages.push(JSON.parse(raw)) }, "herdr:sync-pane");
  assert.deepEqual(cancelMessages.map((message) => message.type), ["session_cancelled"]);
  releaseSendKeys();
  await Promise.resolve();
  assert(!cancelMessages.some((message) => message.type === "turn_ended"), "cancel acknowledgement must not end the Herdr turn");
  HerdrAdapter.sendKeys = originalSendKeys;

  agentStatus = "idle";
  await waitFor(() => messages.some((message) =>
    message.type === "turn_ended" && message.sessionId === "herdr:sync-pane"));

  ws.send(JSON.stringify({ type: "close_session", sessionId: "herdr:sync-pane" }));
  await waitFor(() => messages.some((message) =>
    message.type === "session_closed" && message.sessionId === "herdr:sync-pane"));
  assert.equal(closedPane, "sync-pane", "closing a Herdr session must close its pane");
} finally {
  ws.close();
  await app.stop();
  HerdrTailerRegistry.cleanupAll();
  await new Promise((resolve) => herdrServer.close(resolve));
  rmSync(tmpDir, { recursive: true, force: true });
}

console.log("Herdr session operations: 5 passed, 0 failed");
process.exit(0);
