import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

console.log("=== Testing 17-Agent Registry Matrix ===");

const here = dirname(fileURLToPath(import.meta.url));
const registry = JSON.parse(readFileSync(join(here, "../dist/registry/agents.json"), "utf8"));

// Herdr's canonical agent kinds (from `herdr agent start --kind`).
const HERDR_KINDS = new Set([
  "pi", "claude", "codex", "gemini", "cursor", "devin", "agy", "cline", "omp",
  "mastracode", "opencode", "copilot", "kimi", "kiro", "droid", "amp", "grok",
  "hermes", "kilo", "qodercli", "qwen", "maki", "muse",
]);

// Nexus id → { executables, herdrKind, integration, native }
const EXPECTED = {
  omp: { executables: ["omp"], kind: "omp", integration: "omp", native: "omp" },
  claude: { executables: ["claude"], kind: "claude", integration: "claude", native: null },
  codex: { executables: ["codex"], kind: "codex", integration: "codex", native: null },
  opencode: { executables: ["opencode"], kind: "opencode", integration: "opencode", native: "opencode" },
  cursor: { executables: ["agent", "cursor-agent"], kind: "cursor", integration: "cursor", native: "agent" },
  copilot: { executables: ["copilot"], kind: "copilot", integration: "copilot", native: null },
  devin: { executables: ["devin"], kind: "devin", integration: "devin", native: null },
  droid: { executables: ["droid"], kind: "droid", integration: "droid", native: null },
  kimi: { executables: ["kimi"], kind: "kimi", integration: "kimi", native: "kimi" },
  qwen: { executables: ["qwen"], kind: "qwen", integration: "qwen", native: null },
  grok: { executables: ["grok"], kind: "grok", integration: "grok", native: null },
  pi: { executables: ["pi"], kind: "pi", integration: "pi", native: null },
  kilo: { executables: ["kilo"], kind: "kilo", integration: "kilo", native: null },
  hermes: { executables: ["hermes"], kind: "hermes", integration: "hermes", native: null },
  qodercli: { executables: ["qodercli"], kind: "qodercli", integration: "qodercli", native: null },
  mastracode: { executables: ["mastracode"], kind: "mastracode", integration: "mastracode", native: null },
  "antigravity-cli": { executables: ["agy"], kind: "agy", integration: "antigravity-cli", native: null },
};

assert.equal(registry.agents.length, 17, "registry must contain exactly 17 agents");

const seenIds = new Set();
for (const agent of registry.agents) {
  const expected = EXPECTED[agent.id];
  assert(expected, `unexpected agent id in registry: ${agent.id}`);
  seenIds.add(agent.id);

  assert(agent.name && agent.name.length > 0, `${agent.id}: name required`);
  assert(agent.description && agent.description.length > 0, `${agent.id}: description required`);
  assert(!/Inflection/i.test(agent.description), `${agent.id}: stale Pi description`);

  assert.deepEqual(
    agent.detection?.executables,
    expected.executables,
    `${agent.id}: detection executables`,
  );
  assert(
    HERDR_KINDS.has(agent.herdr?.kind),
    `${agent.id}: herdr.kind "${agent.herdr?.kind}" must be a real Herdr kind`,
  );
  assert.equal(agent.herdr.kind, expected.kind, `${agent.id}: herdr.kind mapping`);
  assert.equal(agent.herdr.integration, expected.integration, `${agent.id}: herdr integration`);
  assert.equal(agent.herdr.enabled, true, `${agent.id}: herdr must be enabled`);

  if (expected.native) {
    assert.equal(agent.native.enabled, true, `${agent.id}: native must be enabled`);
    assert.equal(agent.native.command, expected.native, `${agent.id}: native command`);
    assert.deepEqual(agent.native.args, ["acp"], `${agent.id}: native args must be acp`);
    assert.equal(agent.capabilities.nativeAcp, true, `${agent.id}: nativeAcp capability`);
  } else {
    assert.equal(agent.native.enabled, false, `${agent.id}: native must be disabled`);
    assert.equal(agent.capabilities.nativeAcp, false, `${agent.id}: nativeAcp capability`);
  }
}

assert.equal(seenIds.size, 17, "all 17 expected ids present");

console.log("ALL 17-AGENT REGISTRY MATRIX TESTS PASSED!");
