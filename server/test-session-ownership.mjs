import { EventEmitter } from "node:events";
import { sessionManager } from "./dist/session-manager.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) passed += 1;
  else { failed += 1; console.error(`FAIL: ${message}`); }
}

function ws() {
  const socket = new EventEmitter();
  socket.sent = [];
  socket.send = (message) => socket.sent.push(message);
  return socket;
}

async function main() {
  // ── Empty-state invariants ─────────────────────────────────
  // SessionManager is the sole owner; no sessions before ACP create.
  assert(sessionManager.getSession("nonexistent") === undefined, "getSession returns undefined for missing session");
  assert(sessionManager.getAllSessions().size === 0, "getAllSessions returns empty map with no sessions");
  assert(sessionManager.getActiveSessionIds().size === 0, "getActiveSessionIds returns empty set with no sessions");
  assert(sessionManager.findSessionForWs(ws()) === undefined, "findSessionForWs returns undefined for unknown socket");

  // ── Missing-session safety ─────────────────────────────────
  // buffer/replay/reclaim all degrade gracefully without real sessions.
  assert(
    sessionManager.bufferAgentEvent("nonexistent", { type: "test" }) === undefined,
    "bufferAgentEvent returns undefined for missing session",
  );

  const replay = sessionManager.replayBuffer("nonexistent", "");
  assert(Array.isArray(replay.entries) && replay.entries.length === 0, "replayBuffer entries empty for missing session");
  assert(replay.overflow === false, "replayBuffer overflow false for missing session");

  assert(
    sessionManager.reclaimOrphanedSession("nonexistent", ws()) === undefined,
    "reclaimOrphanedSession returns undefined for missing session",
  );

  // ── Tool-call ID bounding ──────────────────────────────────
  // trimToolCallIds enforces the MAX_TOOLCALL_IDS ceiling on any source.
  const bounded = { toolCallIdMap: new Map() };
  for (let i = 0; i < 600; i++) bounded.toolCallIdMap.set(`key-${i}`, `${i}`);
  sessionManager.trimToolCallIds(bounded);
  assert(bounded.toolCallIdMap.size === 500, "trimToolCallIds trims to 500");
  assert(bounded.toolCallIdMap.has("key-599"), "trim keeps newest entries");
  assert(!bounded.toolCallIdMap.has("key-0"), "trim drops oldest entries");

  // trimToolCallIds is a no-op when under the limit.
  const small = { toolCallIdMap: new Map() };
  for (let i = 0; i < 100; i++) small.toolCallIdMap.set(`k-${i}`, `${i}`);
  sessionManager.trimToolCallIds(small);
  assert(small.toolCallIdMap.size === 100, "trimToolCallIds no-op when under limit");

  // ── WebSocket operation ordering ───────────────────────────
  // enqueueWsOp serialises operations per connection.
  const queueWs = ws();
  const order = [];
  sessionManager.enqueueWsOp(queueWs, async () => { order.push(1); });
  sessionManager.enqueueWsOp(queueWs, async () => { order.push(2); });
  await new Promise((resolve) => setTimeout(resolve, 0));
  assert(order.join(",") === "1,2", "enqueueWsOp maintains per-WebSocket ordering");

  // ── Independent per-WS queues ──────────────────────────────
  // Each WebSocket gets its own serialisation domain.
  const wsA = ws();
  const wsB = ws();
  const orderA = [];
  const orderB = [];
  sessionManager.enqueueWsOp(wsA, async () => { await new Promise((r) => setTimeout(r, 5)); orderA.push("a1"); });
  sessionManager.enqueueWsOp(wsB, async () => { orderB.push("b1"); });
  sessionManager.enqueueWsOp(wsB, async () => { orderB.push("b2"); });
  sessionManager.enqueueWsOp(wsA, async () => { orderA.push("a2"); });
  await new Promise((resolve) => setTimeout(resolve, 20));
  assert(orderA.join(",") === "a1,a2", "separate WS queue A ordering");
  assert(orderB.join(",") === "b1,b2", "separate WS queue B ordering");

  console.log(`Session ownership: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => { console.error(error); process.exit(1); });
