import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createFakeHerdr } from "./fake-herdr.mjs";

console.log("=== Testing agentId -> Herdr kind mapping ===");

const storeDir = mkdtempSync(join(tmpdir(), "nexus-kind-store-"));
const previousStoreDir = process.env.NEXUS_AGENTS_STORE_DIR;
process.env.NEXUS_AGENTS_STORE_DIR = storeDir;
mkdirSync(storeDir, { recursive: true });
writeFileSync(
  join(storeDir, "installed-agents.json"),
  JSON.stringify({
    agents: [
      { agentId: "antigravity-cli", installedAt: Date.now(), source: "registry" },
      { agentId: "cursor", installedAt: Date.now(), source: "registry" },
    ],
  }),
  "utf8",
);

const fakeHerdr = createFakeHerdr();

const { handleCreateHerdrAgent } = await import("../dist/handlers/herdr-actions.mjs");
const { HerdrAdapter } = await import("../dist/discovery/herdr-adapter.mjs");

const originalStart = HerdrAdapter.startAgent;
const originalClose = HerdrAdapter.closePane;

const starts = [];
const closed = [];

/** Drives the real code path: pane resolution, split/tab and start are real. */
const run = async (payload, overrides = {}) => {
  const sent = [];
  const ws = { send: (raw) => sent.push(JSON.parse(raw)) };
  HerdrAdapter.startAgent = async (options) => {
    starts.push(options);
    return overrides.startAgent ? overrides.startAgent(options) : true;
  };
  HerdrAdapter.closePane = async (paneId) => { closed.push(paneId); };
  await handleCreateHerdrAgent(ws, payload);
  return sent;
};

try {
  // 1. The Nexus id is translated to Herdr's kind (antigravity-cli -> agy) and
  //    the split targets a real pane taken from `pane list`, not a workspace id.
  {
    const sent = await run({ workspaceId: "w1", agentId: "antigravity-cli" });
    const done = sent.at(-1);
    assert.equal(done.type, "create_herdr_agent_done", "creation replies");
    assert.equal(done.ok, true, "creation succeeds");
    assert.equal(done.agent, "antigravity-cli", "the reply keeps the Nexus id");
    assert.equal(done.kind, "agy", "the reply exposes the resolved Herdr kind");

    const split = fakeHerdr.calls().find((c) => c[0] === "pane" && c[1] === "split");
    assert(split, "pane split was invoked");
    const paneFlag = split.indexOf("--pane");
    assert(paneFlag >= 0, "pane split received an explicit --pane");
    assert.equal(split[paneFlag + 1], "w1:p1", "the split target is a pane id from pane list");
    assert(!split.includes("w1") || split[paneFlag + 1] !== "w1", "a workspace id is never used as the split target");
    assert(
      fakeHerdr.calls().some((c) => c[0] === "pane" && c[1] === "list" && c.includes("--workspace")),
      "pane list was consulted for the workspace",
    );

    const started = starts.at(-1);
    assert.equal(started.kind, "agy", "agent start received the Herdr kind, not the Nexus id");
    assert.notEqual(started.kind, "antigravity-cli", "the Nexus id is never sent to Herdr");
    assert.equal(started.pane_id, "w1:pSPLIT", "the agent starts in the pane that was created");
  }

  // 2. A second mapping proves the translation is per-agent, not global.
  {
    const sent = await run({ workspaceId: "w1", agentId: "cursor" });
    assert.equal(sent.at(-1).kind, "cursor", "cursor maps to its own kind");
    assert.equal(starts.at(-1).kind, "cursor", "cursor start uses its Herdr kind");
  }

  // 3. An unknown id fails without touching Herdr.
  {
    const before = starts.length;
    const sent = await run({ workspaceId: "w1", agentId: "not-a-real-agent" });
    assert.equal(sent.at(-1).ok, false, "unknown agent fails");
    assert.equal(sent.at(-1).error, "UNKNOWN_AGENT_KIND", "unknown agent reports UNKNOWN_AGENT_KIND");
    assert.equal(starts.length, before, "no agent start is attempted for an unknown agent");
  }

  // 4. A workspace with no panes cannot be split; the handler falls back to a tab.
  {
    fakeHerdr.setState({ panes: [] });
    starts.length = 0;
    const sent = await run({ workspaceId: "empty-ws", agentId: "cursor" });
    assert.equal(sent.at(-1).ok, true, "an empty workspace still gets an agent via tab.create");
    assert.equal(starts.at(-1).pane_id, "w1:p9", "the agent starts in the tab's root pane");
    fakeHerdr.setState({ panes: undefined });
  }

  // 5. A failed start closes the pane it created.
  {
    closed.length = 0;
    const sent = await run(
      { workspaceId: "w1", agentId: "cursor" },
      { startAgent: async () => { throw new Error("agent_pane_busy"); } },
    );
    assert.equal(sent.at(-1).ok, false, "a failed start reports failure");
    assert.deepEqual(closed, ["w1:pSPLIT"], "the pane created for the failed start is closed");
  }

  // 6. A falsy start result is treated as failure and also releases the pane.
  {
    closed.length = 0;
    const sent = await run(
      { workspaceId: "w1", agentId: "cursor" },
      { startAgent: async () => false },
    );
    assert.equal(sent.at(-1).ok, false, "a falsy start result fails");
    assert.deepEqual(closed, ["w1:pSPLIT"], "a falsy start result still releases the pane");
  }
} finally {
  HerdrAdapter.startAgent = originalStart;
  HerdrAdapter.closePane = originalClose;
  fakeHerdr.cleanup();
  if (previousStoreDir === undefined) delete process.env.NEXUS_AGENTS_STORE_DIR;
  else process.env.NEXUS_AGENTS_STORE_DIR = previousStoreDir;
  rmSync(storeDir, { recursive: true, force: true });
}

console.log("ALL AGENT KIND MAPPING TESTS PASSED!");
