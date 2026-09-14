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

// Herdr's integration targets (from `herdr integration install --help`).
const HERDR_INTEGRATIONS = new Set([
  "pi", "omp", "claude", "codex", "copilot", "devin", "droid", "kimi", "opencode",
  "kilo", "hermes", "qodercli", "qwen", "cursor", "mastracode", "antigravity-cli", "grok",
]);

// Nexus id → expected contract. Native ACP is structured by construction, so any
// native-enabled agent declares structuredHistory; herdr does so only where a
// transcript parser exists in this repo (omp jsonl, codex rollout jsonl).
const EXPECTED = {
  omp: { executables: ["omp"], kind: "omp", integration: "omp", native: "omp", nativeHistory: true, herdrHistory: true },
  claude: { executables: ["claude"], kind: "claude", integration: "claude", native: "claude-agent-acp", nativeHistory: true, herdrHistory: false },
  // Codex rollouts are only resolvable through a Linux /proc scan plus an
  // omp-specific session search, so the Herdr backend is terminal-only for now.
  codex: { executables: ["codex"], kind: "codex", integration: "codex", native: "codex-acp", nativeHistory: true, herdrHistory: false },
  opencode: { executables: ["opencode"], kind: "opencode", integration: "opencode", native: "opencode", nativeHistory: true, herdrHistory: false },
  cursor: { executables: ["agent", "cursor-agent"], kind: "cursor", integration: "cursor", native: "agent", nativeHistory: true, herdrHistory: false },
  copilot: { executables: ["copilot"], kind: "copilot", integration: "copilot", native: null, nativeHistory: false, herdrHistory: false },
  devin: { executables: ["devin"], kind: "devin", integration: "devin", native: null, nativeHistory: false, herdrHistory: false },
  droid: { executables: ["droid"], kind: "droid", integration: "droid", native: null, nativeHistory: false, herdrHistory: false },
  kimi: { executables: ["kimi"], kind: "kimi", integration: "kimi", native: "kimi", nativeHistory: true, herdrHistory: false },
  qwen: { executables: ["qwen"], kind: "qwen", integration: "qwen", native: null, nativeHistory: false, herdrHistory: false },
  grok: { executables: ["grok"], kind: "grok", integration: "grok", native: null, nativeHistory: false, herdrHistory: false },
  pi: { executables: ["pi"], kind: "pi", integration: "pi", native: "pi-acp", nativeHistory: true, herdrHistory: false },
  kilo: { executables: ["kilo"], kind: "kilo", integration: "kilo", native: null, nativeHistory: false, herdrHistory: false },
  hermes: { executables: ["hermes"], kind: "hermes", integration: "hermes", native: null, nativeHistory: false, herdrHistory: false },
  qodercli: { executables: ["qodercli"], kind: "qodercli", integration: "qodercli", native: null, nativeHistory: false, herdrHistory: false },
  mastracode: { executables: ["mastracode"], kind: "mastracode", integration: "mastracode", native: null, nativeHistory: false, herdrHistory: false },
  "antigravity-cli": { executables: ["agy"], kind: "agy", integration: "antigravity-cli", native: null, nativeHistory: false, herdrHistory: false },
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

  // Capabilities now live per backend; a shared flat object must not return.
  assert.equal(agent.capabilities, undefined, `${agent.id}: top-level capabilities must be gone`);

  assert.deepEqual(
    agent.detection?.executables,
    expected.executables,
    `${agent.id}: detection executables`,
  );
  assert(HERDR_KINDS.has(agent.herdr?.kind), `${agent.id}: herdr.kind "${agent.herdr?.kind}" must be a real Herdr kind`);
  assert.equal(agent.herdr.kind, expected.kind, `${agent.id}: herdr.kind mapping`);
  assert(
    HERDR_INTEGRATIONS.has(agent.herdr?.integration),
    `${agent.id}: herdr.integration "${agent.herdr?.integration}" must be a real Herdr integration target`,
  );
  assert.equal(agent.herdr.integration, expected.integration, `${agent.id}: herdr integration`);
  assert.equal(agent.herdr.enabled, true, `${agent.id}: herdr must be enabled`);
  assert.equal(agent.herdr.structuredHistory, expected.herdrHistory, `${agent.id}: herdr.structuredHistory`);

  if (expected.native) {
    assert.equal(agent.native.enabled, true, `${agent.id}: native must be enabled`);
    assert.equal(agent.native.command, expected.native, `${agent.id}: native command`);
    if (agent.native.adapterPackage) {
      assert.deepEqual(agent.native.args ?? [], [], `${agent.id}: adapter native args`);
    } else {
      assert.deepEqual(agent.native.args, ["acp"], `${agent.id}: native args must be acp`);
    }
    assert.equal(agent.native.structuredHistory, true, `${agent.id}: native.structuredHistory`);
    assert.equal(agent.native.modelSelection, true, `${agent.id}: native.modelSelection`);
    assert.equal(agent.native.modeSelection, true, `${agent.id}: native.modeSelection`);
    assert.equal(agent.native.authentication, true, `${agent.id}: native.authentication`);
  } else {
    assert.equal(agent.native.enabled, false, `${agent.id}: native must be disabled`);
    assert.equal(agent.native.structuredHistory, false, `${agent.id}: native.structuredHistory`);
  }
  assert.equal(agent.native.structuredHistory, expected.nativeHistory, `${agent.id}: native structuredHistory contract`);
}

assert.equal(seenIds.size, 17, "all 17 expected ids present");

console.log("ALL 17-AGENT REGISTRY MATRIX TESTS PASSED!");
