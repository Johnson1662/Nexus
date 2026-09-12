import assert from "node:assert";
import { HerdrAdapter, HerdrEventBus } from "../dist/discovery/herdr-adapter.mjs";

console.log("=== Testing Herdr Extended API ===");

if (!HerdrAdapter.isAvailable()) {
  console.log("Herdr socket not available, skipping live test");
  process.exit(0);
}

// 1. Test listWorkspaces
const workspaces = await HerdrAdapter.listWorkspaces();
console.log(`Found ${workspaces.length} workspaces:`, workspaces.map(w => ({ id: w.workspace_id, label: w.label })));
assert(Array.isArray(workspaces), "workspaces should be an array");
assert(workspaces.length > 0, "should find at least one workspace in live Herdr");
assert(workspaces[0].workspace_id, "workspace should have workspace_id");

// 2. Test HerdrEventBus
HerdrEventBus.start();
let eventReceived = false;
const unsub = HerdrEventBus.addListener((ev) => {
  eventReceived = true;
  console.log("HerdrEventBus received event:", ev);
});
assert(typeof unsub === "function", "addListener should return unsubscribe function");
unsub();

console.log("\nALL EXTENDED API TESTS PASSED!");
process.exit(0);
