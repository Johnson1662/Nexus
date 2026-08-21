import { Buffer } from "node:buffer";

import { sessionManager } from "./dist/session-manager.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) passed += 1;
  else {
    failed += 1;
    console.error(`FAIL: ${message}`);
  }
}

function fakeTransport() {
  return { send() {} };
}

const sessions = sessionManager.getAllSessions();
const sessionId = "payload-budget-test";
const session = {
  ws: fakeTransport(),
  ownerTransport: null,
  messageBuffer: [],
  replayBytes: 0,
};
sessions.set(sessionId, session);

try {
  const result = sessionManager.bufferAgentEvent(sessionId, {
    type: "agent_event",
    sessionId,
    event: {
      sessionUpdate: "tool_call_update",
      toolCallContent: [{
        type: "content",
        content: { type: "text", text: "字".repeat(3 * 1024 * 1024) },
      }],
    },
  });
  const entry = session.messageBuffer[0];
  const serialized = entry?.payload ?? "";
  const parsed = JSON.parse(serialized);
  assert(Buffer.byteLength(serialized, "utf8") <= 512 * 1024, "single oversized event stays below the 512KB entry cap");
  assert(entry?.payloadBytes === Buffer.byteLength(serialized, "utf8"), "payload byte accounting uses UTF-8 bytes");
  assert(parsed.event?.truncated === true, "oversized event is explicitly marked truncated");
  assert(parsed.event?.originalBytes > 3 * 1024 * 1024, "truncation metadata preserves the original UTF-8 size");
  assert(result?.messageId === entry?.messageId, "bounded replay payload keeps its message id");
  assert(session.replayBytes <= 2 * 1024 * 1024, "single oversized event cannot bypass the 2MB replay budget");
} finally {
  sessions.delete(sessionId);
}

console.log(`Payload budget: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
