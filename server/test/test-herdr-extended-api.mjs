import assert from "node:assert";
import { HerdrAdapter } from "../dist/discovery/herdr-adapter.mjs";

console.log("=== Testing Herdr Extended API ===");

if (!HerdrAdapter.isAvailable()) {
  console.log("Herdr CLI not available, skipping live test");
  process.exit(0);
}

const probe = await HerdrAdapter.probe(true);
if (!probe.available) {
  console.log(`Herdr daemon not reachable (${probe.reason ?? "unknown"}), skipping live test`);
  process.exit(0);
}

// 1. Live workspace listing through the CLI.
const workspaces = await HerdrAdapter.listWorkspaces();
console.log(`Found ${workspaces.length} workspaces:`, workspaces.map(w => ({ id: w.workspace_id, label: w.label })));
assert(Array.isArray(workspaces), "workspaces should be an array");
assert(workspaces.length > 0, "should find at least one workspace in live Herdr");
assert(workspaces[0].workspace_id, "workspace should have workspace_id");

// 2. Agent listing exposes the fields the resolver depends on.
const agents = await HerdrAdapter.listAgents();
assert(Array.isArray(agents), "agents should be an array");
if (agents.length > 0) {
  assert(typeof agents[0].pane_id === "string", "agent should have pane_id");
  assert(typeof agents[0].agent_status === "string", "agent should have agent_status");

  // 3. Strict per-agent status query agrees with the list view.
  const agent = await HerdrAdapter.getAgent(agents[0].pane_id);
  assert.equal(agent.pane_id, agents[0].pane_id, "getAgent returns the requested pane");
  console.log(`agent ${agent.pane_id} status=${agent.agent_status}`);

  // 4. waitForStatus resolves immediately for an already-matching state.
  const status = await HerdrAdapter.waitForStatus(agents[0].pane_id, ["idle", "working", "blocked", "done"], 1000);
  assert(["idle", "working", "blocked", "done", "unknown"].includes(status), `valid status: ${status}`);
  console.log(`waitForStatus -> ${status}`);
}

// 5. Integration status is parsed from the CLI text output.
const integrations = await HerdrAdapter.getIntegrationStatus();
assert(Object.keys(integrations).length > 0, "integration status should list at least one integration");
assert(Object.values(integrations).every((v) => typeof v === "boolean"), "integration states must be booleans");
console.log(`integrations: ${Object.entries(integrations).filter(([, ok]) => ok).map(([id]) => id).join(", ") || "(none installed)"}`);

console.log("\nALL EXTENDED API TESTS PASSED!");
process.exit(0);
