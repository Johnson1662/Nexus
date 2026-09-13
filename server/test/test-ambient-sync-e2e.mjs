import assert from "node:assert/strict";
import { once } from "node:events";
import net from "node:net";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import WebSocket from "ws";

console.log("=== Testing ambient-sync-e2e ===");

const testDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-ambient-e2e-"));
process.env.NEXUS_DATA_DIR = testDataDir;
process.env.NEXUS_AUTH_TOKEN = "ambient-e2e-token";

const sessionId = "ambient-test-uuid-999";
const transcriptPath = path.join(testDataDir, `${sessionId}.jsonl`);

// Write initial OMP session JSONL
const initialLines = [
  JSON.stringify({
    type: "message",
    id: "msg-1",
    message: {
      role: "user",
      content: [{ type: "text", text: "Please inspect the project" }],
    },
  }),
  JSON.stringify({
    type: "message",
    id: "msg-2",
    message: {
      role: "assistant",
      content: [
        { type: "thinking", text: "Analyzing repository layout..." },
        { type: "text", text: "I found the project files." },
      ],
    },
  }),
];
fs.writeFileSync(transcriptPath, initialLines.join("\n") + "\n", "utf8");

// Mock TCP control server for OMP
let receivedPrompt = null;
let receivedCancel = false;

const mockOmpServer = net.createServer((socket) => {
  let buf = "";
  socket.on("data", (chunk) => {
    buf += chunk.toString("utf8");
    const idx = buf.indexOf("\n");
    if (idx !== -1) {
      const line = buf.slice(0, idx).trim();
      buf = buf.slice(idx + 1);
      const parsed = JSON.parse(line);
      if (parsed.type === "prompt") {
        receivedPrompt = parsed.text;
        socket.write(JSON.stringify({ ok: true }) + "\n");
      } else if (parsed.type === "cancel") {
        receivedCancel = true;
        socket.write(JSON.stringify({ ok: true }) + "\n");
      }
    }
  });
});

await new Promise((resolve) => mockOmpServer.listen(0, "127.0.0.1", resolve));
const mockPort = mockOmpServer.address().port;

// Write ambient claim file
const sessionsDir = path.join(testDataDir, "ambient", "sessions");
fs.mkdirSync(sessionsDir, { recursive: true });
const claimFile = path.join(sessionsDir, `${sessionId}.json`);
fs.writeFileSync(
  claimFile,
  JSON.stringify({
    version: 1,
    agent: "omp",
    sessionId,
    pid: process.pid,
    cwd: testDataDir,
    transcriptPath,
    status: "working",
    updatedAt: Date.now(),
    control: {
      host: "127.0.0.1",
      port: mockPort,
      token: "secret-token-abc",
    },
  }),
  "utf8",
);

// Start Bridge Server
const { createBridgeServer } = await import("../dist/server.mjs");
const app = createBridgeServer({ port: 0 });
await once(app.httpServer, "listening");
const bridgePort = app.httpServer.address().port;

const ws = new WebSocket(`ws://127.0.0.1:${bridgePort}`, {
  headers: { authorization: "Bearer ambient-e2e-token" },
});
await once(ws, "open");

const receivedMessages = [];
ws.on("message", (raw) => {
  try {
    receivedMessages.push(JSON.parse(raw.toString()));
  } catch {}
});

const waitFor = async (predicate, timeoutMs = 4000) => {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() >= deadline) throw new Error("timed out waiting for condition");
    await new Promise((resolve) => setTimeout(resolve, 30));
  }
};

// 1. Test list_sessions returns ambient session
ws.send(JSON.stringify({ type: "list_sessions" }));
await waitFor(() => receivedMessages.some((m) => m.type === "session_list"));

const sessionListMsg = receivedMessages.find((m) => m.type === "session_list");
assert.ok(sessionListMsg, "Should receive session_list");
const ambientEntry = sessionListMsg.sessions.find(
  (s) => s.sessionId === `ambient:omp:${sessionId}` || s.sessionId === sessionId,
);
assert.ok(ambientEntry, "Ambient session should be in session_list");
assert.equal(ambientEntry.source, "ambient");
assert.equal(ambientEntry.agent, "omp");
assert.equal(ambientEntry.status, "running");

// 2. Test load_session
receivedMessages.length = 0;
ws.send(JSON.stringify({ type: "load_session", sessionId: `ambient:omp:${sessionId}` }));

await waitFor(() => receivedMessages.some((m) => m.type === "session_started"));
const startedMsg = receivedMessages.find((m) => m.type === "session_started");
assert.equal(startedMsg.streamMode, "acp");
assert.equal(startedMsg.source, "ambient");
assert.equal(startedMsg.agent, "omp");

await waitFor(() => receivedMessages.some((m) => m.type === "history_full"));
const historyMsg = receivedMessages.find((m) => m.type === "history_full");
assert.ok(historyMsg.events.length >= 1, "Should deliver historical ACP events");

// 3. Test real-time incremental tailing
receivedMessages.length = 0;
const appendLine = JSON.stringify({
  type: "message",
  id: "msg-3",
  message: {
    role: "assistant",
    content: [{ type: "text", text: "Incremental output from terminal" }],
  },
});
fs.appendFileSync(transcriptPath, appendLine + "\n", "utf8");

await waitFor(
  () =>
    receivedMessages.some(
      (m) => m.type === "agent_event" && JSON.stringify(m).includes("Incremental output from terminal"),
    ),
  4000,
);

// 4. Test input -> forwards to OMP control server & acks to client
receivedMessages.length = 0;
ws.send(
  JSON.stringify({
    type: "input",
    sessionId: `ambient:omp:${sessionId}`,
    text: "run tests please",
  }),
);

await waitFor(() => receivedMessages.some((m) => m.type === "input_ack"));
assert.equal(receivedPrompt, "run tests please");

// 5. Test cancel -> forwards to OMP control server & notifies client
receivedMessages.length = 0;
ws.send(
  JSON.stringify({
    type: "cancel",
    sessionId: `ambient:omp:${sessionId}`,
  }),
);

await waitFor(() => receivedMessages.some((m) => m.type === "session_cancelled"));
assert.equal(receivedCancel, true);

// 6. Test close_session -> detaches viewing without killing ambient process or claim
receivedMessages.length = 0;
ws.send(
  JSON.stringify({
    type: "close_session",
    sessionId: `ambient:omp:${sessionId}`,
  }),
);

await waitFor(() => receivedMessages.some((m) => m.type === "session_closed"));
assert.ok(fs.existsSync(claimFile), "Claim file should NOT be removed when closing mobile view");

// Teardown
ws.close();
await new Promise((resolve) => app.httpServer.close(resolve));
mockOmpServer.close();

try {
  fs.rmSync(testDataDir, { recursive: true, force: true });
} catch {}
delete process.env.NEXUS_DATA_DIR;
delete process.env.NEXUS_AUTH_TOKEN;

console.log("ALL TESTS PASSED for ambient-sync-e2e!");
process.exit(0);
