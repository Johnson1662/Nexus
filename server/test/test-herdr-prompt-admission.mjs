import assert from "node:assert/strict";
import { HerdrAdapter, isHerdrCode } from "../dist/discovery/herdr-adapter.mjs";
import { createFakeHerdr } from "./fake-herdr.mjs";

console.log("=== Testing Herdr prompt admission ===");

const fake = createFakeHerdr();
fake.setState({
  status: "idle",
  agents: [{ pane_id: "w1:p1", agent: "omp", agent_status: "idle", cwd: "/tmp" }],
});

try {
  // 1. An idle agent accepts a prompt.
  await HerdrAdapter.sendPrompt("w1:p1", "first");
  const prompts = fake.calls().filter((c) => c[0] === "agent" && c[1] === "prompt");
  assert.equal(prompts.length, 1, "an idle agent receives the prompt");
  assert(prompts[0].includes("first"), "the prompt text is passed through");

  // 2. A working agent refuses, immediately (no retry storm).
  fake.setState({ status: "working" });
  const busy = await HerdrAdapter.sendPrompt("w1:p1", "second").then(() => null, (e) => e);
  assert(busy, "a working agent rejects the prompt");
  assert.equal(busy.herdrCode, "agent_busy", "the rejection carries agent_busy");
  assert(isHerdrCode(busy, "agent_busy"), "agent_busy is recognisable by code");
  const afterBusy = fake.calls().filter((c) => c[0] === "agent" && c[1] === "prompt").length;
  assert.equal(afterBusy, 1, "no prompt was delivered to the working agent");

  // 3. A blocked agent is served by the key endpoint, not by a prompt.
  fake.setState({ status: "blocked" });
  const blocked = await HerdrAdapter.sendPrompt("w1:p1", "third").then(() => null, (e) => e);
  assert.equal(blocked?.herdrCode, "agent_busy", "a blocked agent rejects a plain prompt");

  // 4. A finished agent accepts again.
  fake.setState({ status: "done" });
  await HerdrAdapter.sendPrompt("w1:p1", "fourth");
  const finalCount = fake.calls().filter((c) => c[0] === "agent" && c[1] === "prompt").length;
  assert.equal(finalCount, 2, "a finished agent accepts the next prompt");
} finally {
  fake.cleanup();
}

console.log("ALL HERDR PROMPT ADMISSION TESTS PASSED!");
