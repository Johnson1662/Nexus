import assert from "node:assert/strict";
import { getAgentIdForHerdrKind } from "../dist/registry/registry.mjs";
import { HerdrAdapter } from "../dist/discovery/herdr-adapter.mjs";
import { createFakeHerdr } from "./fake-herdr.mjs";

console.log("=== Testing Herdr kind -> Nexus agent id normalization ===");

// 1. The reverse resolver maps every registry kind back to its canonical id.
assert.equal(getAgentIdForHerdrKind("agy"), "antigravity-cli", "agy maps back to antigravity-cli");
assert.equal(getAgentIdForHerdrKind("cursor"), "cursor", "cursor maps to itself");
assert.equal(getAgentIdForHerdrKind("omp"), "omp", "omp maps to itself");
assert.equal(getAgentIdForHerdrKind("gemini"), null, "a kind with no Nexus agent has no mapping");
assert.equal(getAgentIdForHerdrKind(""), null, "an empty kind has no mapping");

// 2. The adapter boundary returns canonical ids so nothing downstream sees a
//    raw Herdr kind as an agent identity.
const fake = createFakeHerdr();
fake.setState({
  agents: [
    { pane_id: "w1:p1", agent: "agy", agent_status: "idle", cwd: "/tmp" },
    { pane_id: "w1:p2", agent: "cursor", agent_status: "idle", cwd: "/tmp" },
    { pane_id: "w1:p3", agent: "gemini", agent_status: "idle", cwd: "/tmp" },
  ],
});

try {
  const agents = await HerdrAdapter.listAgents();
  assert.deepEqual(
    agents.map((a) => a.agent),
    ["antigravity-cli", "cursor", "gemini"],
    "listAgents returns canonical ids and leaves unmapped kinds untouched",
  );

  const one = await HerdrAdapter.getAgent("w1:p1");
  assert.equal(one.agent, "antigravity-cli", "getAgent also normalizes");

  // resolveSessionFile must key capability lookups off the canonical id.
  const resolved = await HerdrAdapter.resolveSessionFile("w1:p1");
  assert.equal(resolved?.agent, "antigravity-cli", "resolveSessionFile reports the canonical id");
} finally {
  fake.cleanup();
}

console.log("ALL HERDR KIND IDENTITY TESTS PASSED!");
