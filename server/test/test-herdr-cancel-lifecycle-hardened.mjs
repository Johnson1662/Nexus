import assert from "node:assert/strict";
import { handleCancel } from "../dist/handlers/cancel.mjs";
import { HerdrAdapter } from "../dist/discovery/herdr-adapter.mjs";

console.log("=== Testing Hardened Herdr Cancel Lifecycle ===");

const sentMessages = [];
const mockWs = {
  send: (raw) => sentMessages.push(JSON.parse(raw)),
};

let currentStatus = "working";
const origListAgents = HerdrAdapter.listAgents;
const origSendKeys = HerdrAdapter.sendKeys;

try {
  HerdrAdapter.sendKeys = async () => {};
  HerdrAdapter.listAgents = async () => [
    {
      pane_id: "p-test",
      agent: "omp",
      agent_status: currentStatus,
      cwd: "/tmp",
    },
  ];

  handleCancel(mockWs, "herdr:p-test");

  // Immediate ACK
  assert(sentMessages.length >= 1, "should have sent session_cancelled immediately");
  assert.equal(sentMessages[0].type, "session_cancelled");
  assert.equal(sentMessages[0].accepted, true);

  // Transition status to idle
  await new Promise((r) => setTimeout(r, 400));
  currentStatus = "idle";
  await new Promise((r) => setTimeout(r, 500));

  const turnEnded = sentMessages.find((m) => m.type === "turn_ended");
  assert(turnEnded, "should have sent turn_ended after agent became idle");
  assert.equal(turnEnded.sessionId, "herdr:p-test");
} finally {
  HerdrAdapter.listAgents = origListAgents;
  HerdrAdapter.sendKeys = origSendKeys;
}

console.log("ALL HERDR CANCEL LIFECYCLE TESTS PASSED!");
