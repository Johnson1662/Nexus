import { sessionManager } from "../dist/session-manager.mjs";
import { handleLoadSession } from "../dist/handlers/load-session.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) passed += 1;
  else {
    failed += 1;
    console.error(`FAIL: ${message}`);
  }
}

const originalGetOrCreate = sessionManager.getOrCreate;
const originalReplayBuffer = sessionManager.replayBuffer;
const sessionId = "load-replay-envelope-test";
const sent = [];
const transport = {
  send(message) {
    sent.push(JSON.parse(String(message)));
  },
};

sessionManager.getOrCreate = async () => ({ sessionId });
sessionManager.replayBuffer = () => ({
  overflow: false,
  entries: [{
    messageId: `${sessionId}:1`,
    payload: JSON.stringify({
      type: "agent_event",
      sessionId,
      event: { sessionUpdate: "agent_message_chunk", text: "replayed" },
      messageId: `${sessionId}:1`,
    }),
    payloadBytes: 128,
    timestamp: Date.now(),
  }],
});

try {
  await handleLoadSession(transport, { sessionId, lastMessageId: `${sessionId}:0` });
  const sync = sent.find((message) => message.type === "sync_response");
  const replay = sync?.entries?.[0]?.payload;
  assert(sync?.sessionId === sessionId, "load replay response is scoped to the requested session");
  assert(replay?.type === "agent_event", "load replay preserves the outer protocol type");
  assert(replay?.sessionId === sessionId, "load replay preserves the outer session id");
  assert(replay?.event?.sessionUpdate === "agent_message_chunk", "load replay preserves the ACP event body");
  assert(replay?.messageId === `${sessionId}:1`, "load replay preserves the replay cursor message id");
} catch (error) {
  failed += 1;
  console.error(`FAIL: load replay handler: ${error instanceof Error ? error.message : String(error)}`);
} finally {
  sessionManager.getOrCreate = originalGetOrCreate;
  sessionManager.replayBuffer = originalReplayBuffer;
}

console.log(`Load replay: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
