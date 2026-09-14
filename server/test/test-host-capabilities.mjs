import assert from "node:assert/strict";
import { detectHostCapabilities } from "../dist/discovery/host-capabilities.mjs";

console.log("=== Testing HostCapabilities Engine ===");

const caps = await detectHostCapabilities(true);
assert(caps, "capabilities must be returned");
assert(["linux", "darwin", "win32"].includes(caps.platform), `valid platform: ${caps.platform}`);
assert(typeof caps.arch === "string" && caps.arch.length > 0, "arch must be string");
assert(typeof caps.git === "object" && typeof caps.git.available === "boolean", "git capability check");
assert(typeof caps.herdr === "object" && typeof caps.herdr.available === "boolean", "herdr capability check");

assert(Array.isArray(caps.agents), "agents must be array");
assert.equal(caps.agents.length, 17, "must have all 17 agents");

for (const agent of caps.agents) {
  assert.equal(typeof agent.enabled, "boolean", `${agent.id}: enabled must be boolean`);
  for (const backend of ["native", "herdr"]) {
    const cap = agent[backend];
    assert.equal(typeof cap.supported, "boolean", `${agent.id}.${backend}: supported`);
    assert.equal(typeof cap.ready, "boolean", `${agent.id}.${backend}: ready`);
    for (const flag of ["structuredHistory", "modelSelection", "modeSelection", "authentication"]) {
      assert.equal(typeof cap[flag], "boolean", `${agent.id}.${backend}.${flag} must be boolean`);
    }
  }
  assert.equal(
    typeof agent.herdr.integrationInstalled,
    "boolean",
    `${agent.id}: integrationInstalled must be boolean`,
  );
}

// Antigravity maps to Herdr's `agy` kind, never its Nexus id.
const agy = caps.agents.find((a) => a.id === "antigravity-cli");
assert(agy, "antigravity-cli must exist");
assert.equal(agy.herdr.kind, "agy", "antigravity-cli herdr.kind must be agy");
assert.equal(agy.herdr.integrationId, "antigravity-cli", "antigravity-cli integrationId");

// Cursor: native structured, Herdr terminal-only.
const cursor = caps.agents.find((a) => a.id === "cursor");
assert(cursor, "cursor must exist");
assert.equal(cursor.native.supported, true, "cursor native ACP is enabled");
assert.equal(cursor.native.structuredHistory, true, "cursor native history is structured");
assert.equal(cursor.herdr.kind, "cursor", "cursor herdr.kind must be cursor");
assert.equal(cursor.herdr.structuredHistory, false, "cursor herdr history is terminal-only");

// OMP: structured on both backends; authentication is native-only.
const omp = caps.agents.find((a) => a.id === "omp");
assert(omp, "omp must exist");
assert.equal(omp.native.supported, true, "omp native ACP is enabled");
assert.equal(omp.native.structuredHistory, true, "omp native history is structured");
assert.equal(omp.herdr.structuredHistory, true, "omp herdr history is structured");
assert.equal(omp.herdr.authentication, false, "omp herdr has no authentication");

// Codex: no native backend and, until a cross-platform transcript resolver
// exists, no structured Herdr history either.
const codex = caps.agents.find((a) => a.id === "codex");
assert(codex, "codex must exist");
assert.equal(codex.native.supported, true, "codex supports native ACP via adapter");
assert.equal(codex.native.adapterRequired, true, "codex requires an ACP adapter");
assert.equal(codex.native.adapterPackage, "@agentclientprotocol/codex-acp", "codex adapter package");
assert.equal(codex.native.adapterBinary, "codex-acp", "codex adapter binary");
assert.equal(codex.herdr.structuredHistory, false, "codex herdr history is terminal-only");

const claude = caps.agents.find((a) => a.id === "claude");
assert(claude, "claude must exist");
assert.equal(claude.native.supported, true, "claude supports native ACP via adapter");
assert.equal(claude.native.adapterRequired, true, "claude requires an ACP adapter");
assert.equal(claude.native.adapterPackage, "@agentclientprotocol/claude-agent-acp", "claude adapter package");
assert.equal(claude.native.adapterBinary, "claude-agent-acp", "claude adapter binary");

const pi = caps.agents.find((a) => a.id === "pi");
assert(pi, "pi must exist");
assert.equal(pi.herdr.kind, "pi", "pi herdr.kind must be pi");
assert.equal(pi.native.supported, true, "pi supports native ACP via adapter");
assert.equal(pi.native.adapterRequired, true, "pi requires an ACP adapter");
assert.equal(pi.native.adapterPackage, "pi-acp", "pi adapter package");
assert.equal(pi.native.adapterBinary, "pi-acp", "pi adapter binary");

console.log("ALL HOST CAPABILITIES TESTS PASSED!");
