import assert from "node:assert/strict";
import {
  listRegistryAgents,
  getNativeConfig,
  getHerdrConfig,
  isValidNativeConfig,
  isValidHerdrConfig,
} from "../dist/registry/registry.mjs";

console.log("=== Testing Agent Capability Matrix ===");

const agents = listRegistryAgents();
assert(agents.length >= 17, `Expected at least 17 registry agents, got ${agents.length}`);

for (const agent of agents) {
  assert.ok(agent.id, "Agent must have an id");
  assert.ok(agent.name, `Agent ${agent.id} must have a name`);
  assert.equal(
    isValidNativeConfig(agent.native),
    true,
    `Agent ${agent.id} has invalid native config`,
  );
  assert.equal(
    isValidHerdrConfig(agent.herdr),
    true,
    `Agent ${agent.id} has invalid herdr config`,
  );

  const native = getNativeConfig(agent.id);
  const herdr = getHerdrConfig(agent.id);
  assert.equal(typeof native.enabled, "boolean", `Agent ${agent.id} native.enabled should be boolean`);
  assert.equal(typeof native.structuredHistory, "boolean", `Agent ${agent.id} native.structuredHistory should be boolean`);
  assert.equal(typeof native.modelSelection, "boolean", `Agent ${agent.id} native.modelSelection should be boolean`);
  assert.equal(typeof native.modeSelection, "boolean", `Agent ${agent.id} native.modeSelection should be boolean`);
  assert.equal(typeof native.authentication, "boolean", `Agent ${agent.id} native.authentication should be boolean`);
  assert.equal(typeof herdr.enabled, "boolean", `Agent ${agent.id} herdr.enabled should be boolean`);
  assert.equal(typeof herdr.structuredHistory, "boolean", `Agent ${agent.id} herdr.structuredHistory should be boolean`);
  assert.equal(typeof herdr.kind, "string", `Agent ${agent.id} herdr.kind should be a string`);
  assert.equal(typeof herdr.integration, "string", `Agent ${agent.id} herdr.integration should be a string`);
}
console.log(`  ✓ Validated backend capability matrix for all ${agents.length} registry agents`);

// Specific key checks
const ompNative = getNativeConfig("omp");
assert.equal(ompNative.enabled, true, "omp must enable native ACP");
assert.equal(ompNative.structuredHistory, true, "omp native history is structured");
assert.equal(ompNative.authentication, true, "omp native supports authentication");
assert.equal(getHerdrConfig("omp").structuredHistory, true, "omp herdr history is structured");

const claudeNative = getNativeConfig("claude");
assert.equal(claudeNative.enabled, false, "claude has no native ACP adapter");
assert.equal(getHerdrConfig("claude").enabled, true, "claude must be available through Herdr");

const codexHerdr = getHerdrConfig("codex");
assert.equal(getNativeConfig("codex").enabled, false, "codex has no native ACP adapter");
assert.equal(
  codexHerdr.structuredHistory,
  false,
  "codex has no cross-platform transcript resolver yet, so its Herdr backend is terminal-only",
);
assert.equal(codexHerdr.kind, "codex", "codex herdr kind");

// Cursor: structured natively, terminal-only through Herdr.
assert.equal(getNativeConfig("cursor").structuredHistory, true, "cursor native history is structured");
assert.equal(getHerdrConfig("cursor").structuredHistory, false, "cursor herdr history is terminal-only");

// Fallback for unknown agent
assert.equal(getNativeConfig("unknown-agent-xyz"), null, "Unknown agent native config is null");
assert.equal(getHerdrConfig("unknown-agent-xyz"), null, "Unknown agent herdr config is null");

console.log("ALL AGENT CAPABILITY MATRIX TESTS PASSED!\n");
