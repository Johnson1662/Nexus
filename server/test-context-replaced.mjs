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

const sessionId = "bridge-session-context-test";
const transport = { send() { } };
const sessions = sessionManager.getAllSessions();
const previous = sessions.get(sessionId);
sessions.set(sessionId, {
  ownerTransport: transport,
  messageBuffer: [],
  replayBytes: 0,
});

try {
  const contextEvent = {
    type: "session_context_replaced",
    sessionId,
    reason: "reload_failed",
    previousAgentSessionId: "agent-session-old",
    newAgentSessionId: "agent-session-new",
  };
  const replayed = sessionManager.bufferAgentEvent(sessionId, contextEvent);
  const buffered = sessions.get(sessionId).messageBuffer[0];
  const bufferedPayload = JSON.parse(buffered.payload);

  assert(replayed?.type === "session_context_replaced", "context replacement event is accepted");
  assert(replayed?.sessionId === sessionId, "bridge session key stays unchanged");
  assert(replayed?.reason === "reload_failed", "reload failure reason is preserved");
  assert(replayed?.previousAgentSessionId === "agent-session-old", "old agent session ID is preserved");
  assert(replayed?.newAgentSessionId === "agent-session-new", "new agent session ID is preserved");
  assert(typeof replayed?.messageId === "string", "buffered event receives a messageId");
  assert(bufferedPayload.type === "session_context_replaced", "replay payload keeps the event type");
  assert(bufferedPayload.sessionId === sessionId, "replay payload keeps the bridge session key");
  assert(bufferedPayload.messageId === replayed?.messageId, "replay payload matches the returned messageId");
  assert(contextEvent.messageId === undefined, "bufferAgentEvent does not mutate the caller event");
} finally {
  if (previous) sessions.set(sessionId, previous);
  else sessions.delete(sessionId);
  sessionManager.stop();
}

console.log(`Context replaced: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
