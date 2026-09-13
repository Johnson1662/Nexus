import assert from "node:assert/strict";
import {
  listRegistryAgents,
  getRegistryAgent,
  getAgentCapabilities,
  isValidCapabilities,
} from "../dist/registry/registry.mjs";
import { resolveAgentInfo } from "../dist/agents-store.mjs";

console.log("=== Testing Agent Capability Matrix ===");

const agents = listRegistryAgents();
assert(agents.length >= 17, `Expected at least 17 registry agents, got ${agents.length}`);

for (const agent of agents) {
  assert.ok(agent.id, "Agent must have an id");
  assert.ok(agent.name, `Agent ${agent.id} must have a name`);
  assert.equal(isValidCapabilities(agent.capabilities), true, `Agent ${agent.id} has invalid capabilities structure`);

  const caps = getAgentCapabilities(agent.id);
  assert.equal(typeof caps.nativeAcp, "boolean", `Agent ${agent.id} nativeAcp should be boolean`);
  assert.equal(typeof caps.herdr, "boolean", `Agent ${agent.id} herdr should be boolean`);
  assert.equal(typeof caps.structuredHistory, "boolean", `Agent ${agent.id} structuredHistory should be boolean`);
  assert.equal(typeof caps.modelSelection, "boolean", `Agent ${agent.id} modelSelection should be boolean`);
  assert.equal(typeof caps.modeSelection, "boolean", `Agent ${agent.id} modeSelection should be boolean`);
  assert.equal(typeof caps.authentication, "boolean", `Agent ${agent.id} authentication should be boolean`);
}
console.log(`  ✓ Validated capabilities matrix for all ${agents.length} registry agents`);

// Specific key checks
const ompCaps = getAgentCapabilities("omp");
assert.equal(ompCaps.nativeAcp, true, "omp must support nativeAcp");
assert.equal(ompCaps.structuredHistory, true, "omp must support structuredHistory");
assert.equal(ompCaps.authentication, true, "omp must support authentication");

const claudeCaps = getAgentCapabilities("claude");
assert.equal(claudeCaps.nativeAcp, false, "claude CLI should not have nativeAcp=true without adapter");
assert.equal(claudeCaps.herdr, true, "claude should support herdr");

const codexCaps = getAgentCapabilities("codex");
assert.equal(codexCaps.nativeAcp, false, "codex CLI should not have nativeAcp=true without adapter");
assert.equal(codexCaps.structuredHistory, true, "codex has structured rollout history");

// Fallback for unknown agent
const fallback = getAgentCapabilities("unknown-agent-xyz");
assert.equal(fallback, null, "Unknown agent capabilities is null");

console.log("ALL AGENT CAPABILITY MATRIX TESTS PASSED!\n");
