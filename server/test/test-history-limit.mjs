import { limitHistoryEvents, MAX_HISTORY_EVENTS } from "../dist/handlers/load-session.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${message}`);
  } else {
    failed += 1;
    console.error(`  ✗ FAIL: ${message}`);
  }
}

console.log("Testing limitHistoryEvents...");

// Short history passes through untouched
{
  const events = [{ sessionUpdate: "agent_message_chunk", content: { text: "hi" } }];
  const out = limitHistoryEvents(events);
  assert(out.truncated === false, "short history is not marked truncated");
  assert(out.total === 1 && out.events.length === 1, "short history keeps all events");
}

// Long history is capped to the tail
{
  const events = Array.from({ length: MAX_HISTORY_EVENTS + 200 }, (_, i) => ({
    sessionUpdate: "agent_message_chunk",
    content: { text: `msg-${i}` },
  }));
  const out = limitHistoryEvents(events);
  assert(out.truncated === true, "long history is marked truncated");
  assert(out.total === MAX_HISTORY_EVENTS + 200, "total records original length");
  assert(out.events.length === MAX_HISTORY_EVENTS, `capped to ${MAX_HISTORY_EVENTS} events`);
  assert(
    out.events[0].content.text === `msg-200`,
    "keeps the tail (most recent) events",
  );
}

// Oversized text blobs are truncated per field
{
  const big = "x".repeat(9000);
  const out = limitHistoryEvents([
    { sessionUpdate: "agent_message_chunk", content: { text: big } },
  ]);
  const text = out.events[0].content.text;
  assert(text.length <= 4001, "oversized text is truncated");
  assert(text.endsWith("…"), "truncation is marked with ellipsis");
}

console.log(`\nHistory limit tests: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
