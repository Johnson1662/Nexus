import assert from "node:assert/strict";
import { HerdrCliError } from "../dist/discovery/herdr-cli.mjs";

console.log("=== Testing Cursor extension round trip ===");

// The dispatcher is a private method; exercise it through a tiny harness that
// mirrors how SessionManager constructs it (extension method in, answer out).
const { sessionManager } = await import("../dist/session-manager.mjs");

const manager = sessionManager;
const dispatch = manager.buildExtMethodCallback.bind(manager);

const broadcast = [];
manager.broadcastToSubscribers = (sessionId, payload) => {
  broadcast.push({ sessionId, payload });
};

let permissionResolver = null;
const permCallback = () =>
  new Promise((resolve) => {
    permissionResolver = resolve;
  });

const extMethod = dispatch(() => "session-cursor", permCallback);

// 1. ask_question: answer selected -> the chosen option comes back to the agent.
{
  const pending = extMethod("cursor/ask_question", {
    question: "Which file?",
    options: [
      { optionId: "a", name: "A" },
      { optionId: "b", name: "B" },
    ],
  });

  assert(permissionResolver, "ask_question surfaces an ACP permission card");
  permissionResolver({ outcome: { outcome: "selected", optionId: "b" } });

  const answer = await pending;
  assert.deepEqual(
    answer,
    { outcome: "answered", answer: { optionId: "b" } },
    "ask_question returns the chosen option id",
  );
}

// 2. ask_question: cancelled -> explicit cancellation, never a fake answer.
{
  const pending = extMethod("cursor/ask_question", { question: "Q", options: [] });
  permissionResolver({ outcome: { outcome: "cancelled" } });
  const answer = await pending;
  assert.deepEqual(answer, { outcome: "cancelled" }, "a cancelled ask returns cancelled");
}

// 3. create_plan: acknowledged and rendered as a plan event.
{
  broadcast.length = 0;
  const answer = await extMethod("cursor/create_plan", {
    entries: [{ content: "step 1", status: "pending", priority: "high" }],
  });
  assert.deepEqual(answer, { ok: true, accepted: true }, "create_plan is acknowledged");
  const planEvent = broadcast.find((entry) => entry.payload?.event?.sessionUpdate === "plan");
  assert(planEvent, "create_plan emits a plan event");
  assert.equal(planEvent.payload.event.planEntries.length, 1, "plan event carries the entries");
  assert.equal(planEvent.sessionId, "session-cursor", "plan event targets the session");
}

// 4. Unknown extensions are tolerated so an agent with extra methods still runs.
{
  const answer = await extMethod("cursor/something_else", {});
  assert.deepEqual(answer, {}, "unknown extension methods return an empty result");
}

console.log("ALL CURSOR EXTENSION ROUND TRIP TESTS PASSED!");
