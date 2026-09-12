import assert from "node:assert";
import fs from "node:fs";
import WebSocket from "ws";

console.log("=== Testing End-to-End Herdr ACP Synchronization ===");

const token = fs.readFileSync(process.env.HOME + "/.nexus/server.token", "utf8").trim();
const ws = new WebSocket(`ws://127.0.0.1:12138?token=${token}`);

let gotSessionStarted = false;
let streamMode = null;
let eventCount = 0;
let gotInputAck = false;
let gotCancelled = false;
let gotTurnEnded = false;
const eventTypes = new Set();

ws.on("open", () => {
  console.log("1. Connected to bridge daemon");
  ws.send(JSON.stringify({ type: "load_session", sessionId: "herdr:w2:p7" }));
});

ws.on("message", (data) => {
  const msg = JSON.parse(data.toString());

  if (msg.type === "session_started") {
    gotSessionStarted = true;
    streamMode = msg.streamMode;
    console.log(`2. Received session_started (streamMode: ${streamMode})`);
  } else if (msg.type === "agent_event") {
    eventCount++;
    if (msg.event?.sessionUpdate) {
      eventTypes.add(msg.event.sessionUpdate);
    }
  } else if (msg.type === "input_ack") {
    gotInputAck = true;
    console.log("3. Received input_ack for injected prompt");
  } else if (msg.type === "session_cancelled") {
    gotCancelled = true;
    console.log("4. Received session_cancelled");
  } else if (msg.type === "turn_ended") {
    gotTurnEnded = true;
    console.log("5. Received turn_ended");
  }
});

// Wait 1.5s for initial load to finish, then test input and cancel
setTimeout(() => {
  assert.strictEqual(gotSessionStarted, true, "session_started should be received");
  assert.strictEqual(streamMode, "acp", "streamMode should be 'acp'");
  assert(eventCount > 50, `Expected >50 ACP events, got ${eventCount}`);
  assert(eventTypes.has("user_message_chunk"), "Should contain user_message_chunk");
  assert(eventTypes.has("tool_call"), "Should contain tool_call");
  console.log(`   Captured event types: ${Array.from(eventTypes).join(", ")}`);

  // Test prompt injection and cancel
  ws.send(JSON.stringify({ type: "input", sessionId: "herdr:w2:p7", text: "echo test" }));

  setTimeout(() => {
    assert.strictEqual(gotInputAck, true, "input_ack should be received");
    ws.send(JSON.stringify({ type: "cancel", sessionId: "herdr:w2:p7" }));

    setTimeout(() => {
      assert.strictEqual(gotCancelled, true, "session_cancelled should be received");
      assert.strictEqual(gotTurnEnded, true, "turn_ended should be received");
      ws.close();
      console.log("\nALL E2E CHECKS PASSED: Live Herdr ACP bidirectional sync verified!");
      process.exit(0);
    }, 500);
  }, 500);
}, 1500);
