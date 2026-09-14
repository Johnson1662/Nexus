import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

console.log("=== Testing ambient-session ===");

const testDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-ambient-test-"));
process.env.NEXUS_DATA_DIR = testDataDir;
const testStoreDir = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-agents-store-ambient-"));
process.env.NEXUS_AGENTS_STORE_DIR = testStoreDir;
fs.writeFileSync(path.join(testStoreDir, "installed-agents.json"), JSON.stringify({
  agents: [{ agentId: "omp", installedAt: Date.now(), source: "registry" }],
}), "utf8");

const {
  listAmbientSessions,
  getAmbientSession,
  sendAmbientCommand,
  watchAmbientSessions,
} = await import("../dist/discovery/ambient-session.mjs");

// 1. Create a dummy transcript file
const transcriptPath = path.join(testDataDir, "dummy-session.jsonl");
fs.writeFileSync(transcriptPath, JSON.stringify({ type: "message", role: "user", text: "hello" }) + "\n", "utf8");

// 2. Start a mock loopback TCP server to simulate the OMP extension
let receivedCommands = [];
let mockServerBehavior = "ok"; // "ok" | "reject"

const mockServer = net.createServer((socket) => {
  let buf = "";
  socket.on("data", (chunk) => {
    buf += chunk.toString("utf8");
    const idx = buf.indexOf("\n");
    if (idx !== -1) {
      const line = buf.slice(0, idx).trim();
      buf = buf.slice(idx + 1);
      const parsed = JSON.parse(line);
      receivedCommands.push(parsed);

      if (mockServerBehavior === "reject" || parsed.token !== "valid-token-123") {
        socket.write(JSON.stringify({ ok: false, error: "unauthorized" }) + "\n");
      } else {
        socket.write(JSON.stringify({ ok: true }) + "\n");
      }
    }
  });
});

await new Promise((resolve) => mockServer.listen(0, "127.0.0.1", resolve));
const mockPort = mockServer.address().port;

const sessionsDir = path.join(testDataDir, "ambient", "sessions");
fs.mkdirSync(sessionsDir, { recursive: true });

// 3. Test claims: valid, expired, invalid agent
const validClaim = {
  version: 1,
  agent: "omp",
  sessionId: "session-valid-001",
  pid: process.pid,
  cwd: testDataDir,
  transcriptPath,
  status: "working",
  updatedAt: Date.now(),
  control: {
    host: "127.0.0.1",
    port: mockPort,
    token: "valid-token-123",
  },
};

const expiredClaim = {
  version: 1,
  agent: "omp",
  sessionId: "session-expired-002",
  pid: process.pid,
  cwd: testDataDir,
  transcriptPath,
  status: "idle",
  updatedAt: Date.now() - 30000, // 30s ago (>15s)
  control: {
    host: "127.0.0.1",
    port: mockPort,
    token: "valid-token-123",
  },
};

const invalidAgentClaim = {
  version: 1,
  agent: "unknown-agent",
  sessionId: "session-invalid-003",
  pid: process.pid,
  cwd: testDataDir,
  transcriptPath,
  status: "idle",
  updatedAt: Date.now(),
  control: {
    host: "127.0.0.1",
    port: mockPort,
    token: "valid-token-123",
  },
};

fs.writeFileSync(path.join(sessionsDir, "session-valid-001.json"), JSON.stringify(validClaim));
fs.writeFileSync(path.join(sessionsDir, "session-expired-002.json"), JSON.stringify(expiredClaim));
fs.writeFileSync(path.join(sessionsDir, "session-invalid-003.json"), JSON.stringify(invalidAgentClaim));

// Test listAmbientSessions
const list = listAmbientSessions();
assert.equal(list.length, 1, "Only the valid OMP session should be returned");
assert.equal(list[0].sessionId, "ambient:omp:session-valid-001");
assert.equal(list[0].status, "running", "working should map to running");

// Verify stale & invalid claims were reaped from disk
assert.ok(!fs.existsSync(path.join(sessionsDir, "session-expired-002.json")), "Expired claim should be deleted");
assert.ok(!fs.existsSync(path.join(sessionsDir, "session-invalid-003.json")), "Invalid agent claim should be deleted");

// Test getAmbientSession
const byPrefixed = getAmbientSession("ambient:omp:session-valid-001");
assert.ok(byPrefixed, "Should find by ambient:omp: prefix");
assert.equal(byPrefixed?.realSessionId, "session-valid-001");

const byRealId = getAmbientSession("session-valid-001");
assert.ok(byRealId, "Should find by real session id");

// Test sendAmbientCommand - prompt
receivedCommands = [];
await sendAmbientCommand("ambient:omp:session-valid-001", { type: "prompt", text: "npm test run" });
assert.equal(receivedCommands.length, 1);
assert.equal(receivedCommands[0].type, "prompt");
assert.equal(receivedCommands[0].text, "npm test run");
assert.equal(receivedCommands[0].token, "valid-token-123");

// Test sendAmbientCommand - cancel
receivedCommands = [];
await sendAmbientCommand("ambient:omp:session-valid-001", { type: "cancel" });
assert.equal(receivedCommands.length, 1);
assert.equal(receivedCommands[0].type, "cancel");

// Test sendAmbientCommand - rejection
mockServerBehavior = "reject";
await assert.rejects(
  async () => {
    await sendAmbientCommand("ambient:omp:session-valid-001", { type: "prompt", text: "will fail" });
  },
  /unauthorized/,
  "Should reject when server returns ok: false",
);
mockServerBehavior = "ok";

// Test watchAmbientSessions
let watchTriggerCount = 0;
const stopWatch = watchAmbientSessions(() => {
  watchTriggerCount++;
});

// Update claim status
validClaim.status = "idle";
validClaim.updatedAt = Date.now();
fs.writeFileSync(path.join(sessionsDir, "session-valid-001.json"), JSON.stringify(validClaim));

await new Promise((resolve) => setTimeout(resolve, 600));
assert.ok(watchTriggerCount >= 1, "Watcher should trigger on claim update");

stopWatch();

// Test that disabling OMP hides ambient sessions
const { uninstallAgent } = await import("../dist/agents-store.mjs");
uninstallAgent("omp");
assert.equal(listAmbientSessions().length, 0, "disabling omp must hide ambient sessions");
assert.equal(getAmbientSession("ambient:omp:session-valid-001"), null, "getAmbientSession returns null when omp is disabled");

// Teardown
mockServer.close();
try {
  fs.rmSync(testDataDir, { recursive: true, force: true });
} catch {}
try {
  fs.rmSync(testStoreDir, { recursive: true, force: true });
} catch {}
delete process.env.NEXUS_DATA_DIR;
delete process.env.NEXUS_AGENTS_STORE_DIR;

console.log("ALL TESTS PASSED for ambient-session!");
