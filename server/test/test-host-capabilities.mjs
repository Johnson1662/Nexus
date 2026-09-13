import assert from "node:assert/strict";
import { detectHostCapabilities } from "../dist/discovery/host-capabilities.mjs";

console.log("=== Testing HostCapabilities Engine ===");

const caps = await detectHostCapabilities(true);
assert(caps, "capabilities must be returned");
assert(["linux", "darwin", "win32"].includes(caps.platform), `valid platform: ${caps.platform}`);
assert(typeof caps.arch === "string" && caps.arch.length > 0, "arch must be string");
assert(typeof caps.git === "object" && typeof caps.git.available === "boolean", "git capability check");
assert(typeof caps.herdr === "object" && typeof caps.herdr.available === "boolean", "herdr capability check");
assert(["unix", "pipe"].includes(caps.herdr.endpointKind), "herdr endpointKind is unix or pipe");

assert(Array.isArray(caps.agents), "agents must be array");
assert.equal(caps.agents.length, 17, "must have all 17 agents");

// Verify Antigravity mapping
const agy = caps.agents.find(a => a.id === "antigravity-cli");
assert(agy, "antigravity-cli must exist");
assert.equal(agy.herdr.kind, "agy", "antigravity-cli herdr.kind must be agy");
assert.equal(agy.herdr.integrationId, "antigravity-cli", "antigravity-cli integrationId");

// Verify Cursor mapping
const cursor = caps.agents.find(a => a.id === "cursor");
assert(cursor, "cursor must exist");
assert.equal(cursor.native.supported, true, "cursor native ACP is enabled");
assert.equal(cursor.herdr.kind, "cursor", "cursor herdr.kind must be cursor");

// Verify OMP mapping
const omp = caps.agents.find(a => a.id === "omp");
assert(omp, "omp must exist");
assert.equal(omp.native.supported, true, "omp native ACP is enabled");
assert.equal(omp.herdr.kind, "omp", "omp herdr.kind must be omp");
assert.equal(omp.structuredHistory, true, "omp structuredHistory must be true");

// Verify Pi mapping
const pi = caps.agents.find(a => a.id === "pi");
assert(pi, "pi must exist");
assert.equal(pi.herdr.kind, "pi", "pi herdr.kind must be pi");

console.log("ALL HOST CAPABILITIES TESTS PASSED!");
