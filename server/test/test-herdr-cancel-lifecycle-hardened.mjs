import assert from "node:assert/strict";
import { handleCancel } from "../dist/handlers/cancel.mjs";
import { HerdrAdapter, isHerdrCode } from "../dist/discovery/herdr-adapter.mjs";
import { HerdrCliError } from "../dist/discovery/herdr-cli.mjs";

console.log("=== Testing Hardened Herdr Cancel Lifecycle ===");

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const originals = {
  sendKeys: HerdrAdapter.sendKeys,
  waitForStatus: HerdrAdapter.waitForStatus,
  getAgent: HerdrAdapter.getAgent,
};

/** Drive one cancel and return the protocol messages it produced. */
async function cancelWith(overrides, { settleMs = 250 } = {}) {
  const sent = [];
  const ws = { send: (raw) => sent.push(JSON.parse(raw)) };
  HerdrAdapter.sendKeys = overrides.sendKeys ?? (async () => {});
  HerdrAdapter.waitForStatus = overrides.waitForStatus ?? (async () => "idle");
  HerdrAdapter.getAgent = overrides.getAgent ?? (async () => ({ pane_id: "p-test", agent: "omp", agent_status: "idle", cwd: "/tmp" }));
  handleCancel(ws, "herdr:p-test");
  await wait(settleMs);
  return sent;
}

const types = (messages) => messages.map((m) => m.type);

try {
  // 1. Herdr confirms the agent stopped: exactly one turn_ended, no cancel_failed.
  {
    const sent = await cancelWith({});
    assert.deepEqual(types(sent), ["session_cancelled", "turn_ended"], "clean cancel acknowledges then ends the turn");
    assert.equal(sent[0].accepted, true, "acknowledgement is marked accepted");
    assert.equal(sent[1].status, "idle", "turn_ended reports the observed status");
    assert.equal(sent.filter((m) => m.type === "turn_ended").length, 1, "exactly one turn_ended");
  }

  // 2. The pane is already gone: the turn cannot continue, so it ends.
  {
    const sent = await cancelWith({
      sendKeys: async () => { throw new HerdrCliError("HERDR_EXIT", "gone", "agent_not_found"); },
    });
    assert.deepEqual(types(sent), ["turn_ended"], "a vanished pane ends the turn without an ack");
    assert.equal(sent[0].status, "gone", "gone status is reported");
  }

  // 3. Signal delivered but the agent never stops: cancel_failed, never turn_ended.
  {
    const sent = await cancelWith({
      waitForStatus: async () => { throw new HerdrCliError("HERDR_TIMEOUT", "wait timed out"); },
      getAgent: async () => ({ pane_id: "p-test", agent: "omp", agent_status: "working", cwd: "/tmp" }),
    });
    assert.deepEqual(types(sent), ["session_cancelled", "cancel_failed"], "a still-working agent reports cancel_failed");
    assert.equal(sent[1].status, "working", "cancel_failed carries the observed status");
    assert(!sent.some((m) => m.type === "turn_ended"), "a stuck agent must never report turn_ended");
  }

  // 4. Transport failure: unverifiable cancellation is a failure, not a success.
  {
    const sent = await cancelWith({
      waitForStatus: async () => { throw new HerdrCliError("HERDR_BIN_NOT_FOUND", "Herdr executable not found"); },
      getAgent: async () => { throw new HerdrCliError("HERDR_BIN_NOT_FOUND", "Herdr executable not found"); },
    });
    assert.deepEqual(types(sent), ["session_cancelled", "cancel_failed"], "a broken transport reports cancel_failed");
    assert(sent[1].error.startsWith("VERIFY_FAILED"), "transport failures are reported as VERIFY_FAILED");
    assert(!sent.some((m) => m.type === "turn_ended"), "an unverifiable cancel must never report turn_ended");
  }

  // 5. The wait itself may report a pane that disappeared mid-cancel.
  {
    const sent = await cancelWith({
      waitForStatus: async () => { throw new HerdrCliError("HERDR_EXIT", "pane gone", "pane_not_found"); },
    });
    assert.deepEqual(types(sent), ["session_cancelled", "turn_ended"], "pane_not_found during the wait ends the turn");
    assert.equal(sent[1].status, "gone", "gone status is reported");
  }

  // 6. isHerdrCode only matches the specific code.
  {
    const err = new HerdrCliError("HERDR_EXIT", "x", "agent_not_found");
    assert.equal(isHerdrCode(err, "agent_not_found"), true, "isHerdrCode matches the Herdr code");
    assert.equal(isHerdrCode(err, "pane_not_found"), false, "isHerdrCode rejects other codes");
    assert.equal(isHerdrCode(new Error("nope"), "agent_not_found"), false, "isHerdrCode rejects plain errors");
  }
} finally {
  HerdrAdapter.sendKeys = originals.sendKeys;
  HerdrAdapter.waitForStatus = originals.waitForStatus;
  HerdrAdapter.getAgent = originals.getAgent;
}

console.log("ALL HERDR CANCEL LIFECYCLE TESTS PASSED!");
