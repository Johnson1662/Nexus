import assert from "node:assert";
import { handleListHerdrWorkspaces, handleFocusHerdrTarget, handleInteractHerdrBlocked } from "../dist/handlers/herdr-actions.mjs";

console.log("=== Testing Herdr Actions Handler ===");

// 1. Test handleListHerdrWorkspaces
let sentMessage = null;
const mockWs = {
  send(data) {
    sentMessage = JSON.parse(data);
  }
};

await handleListHerdrWorkspaces(mockWs);
assert(sentMessage, "should have received a message");
assert.strictEqual(sentMessage.type, "herdr_workspaces_list");
assert(Array.isArray(sentMessage.workspaces), "workspaces should be an array");
console.log("handleListHerdrWorkspaces returned:", sentMessage.workspaces.length, "workspaces");
if (sentMessage.workspaces.length > 0) {
  assert(sentMessage.workspaces[0].workspaceId, "workspace item must have workspaceId");
  assert(sentMessage.workspaces[0].name, "workspace item must have name");
}

// 2. Test handleFocusHerdrTarget
let focusResult = null;
const focusWs = {
  send(data) {
    focusResult = JSON.parse(data);
  }
};
const targetWorkspaceId = sentMessage.workspaces.length > 0 ? sentMessage.workspaces[0].workspaceId : "mock_w1";
await handleFocusHerdrTarget(focusWs, {
  workspaceId: targetWorkspaceId,
});

assert(focusResult, "should receive focus response");
assert.strictEqual(focusResult.type, "focus_herdr_target_done");
if (sentMessage.workspaces.length === 0) {
  assert.strictEqual(focusResult.ok, false);
} else {
  assert.strictEqual(focusResult.ok, true);
}

// 3. Test handleInteractHerdrBlocked
let interactResult = null;
const interactWs = {
  send(data) {
    interactResult = JSON.parse(data);
  }
};
await handleInteractHerdrBlocked(interactWs, { paneId: "mock_p1", key: "enter" });
assert(interactResult, "should receive interact response");
assert.strictEqual(interactResult.type, "interact_herdr_blocked_done");
if (sentMessage.workspaces.length === 0) {
  assert.strictEqual(interactResult.ok, false);
}

console.log("ALL HERDR ACTIONS TESTS PASSED!");
process.exit(0);
