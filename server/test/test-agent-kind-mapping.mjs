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

const originals = {
  splitPane: HerdrAdapter.splitPane,
  createTab: HerdrAdapter.createTab,
  startAgent: HerdrAdapter.startAgent,
  closePane: HerdrAdapter.closePane,
};

const starts = [];
const run = async (payload, overrides = {}) => {
  const sent = [];
  const ws = { send: (raw) => sent.push(JSON.parse(raw)) };
  HerdrAdapter.splitPane = overrides.splitPane ?? (async () => "w1:pNEW");
  HerdrAdapter.createTab = overrides.createTab ?? (async () => "w1:pTAB");
  HerdrAdapter.startAgent = async (options) => {
    starts.push(options);
    return overrides.startAgent ? overrides.startAgent(options) : true;
  };
  HerdrAdapter.closePane = overrides.closePane ?? (async () => {});
  await handleCreateHerdrAgent(ws, payload);
  return sent;
};

try {
  // 1. The Nexus id is translated to Herdr's kind (antigravity-cli -> agy).
  {
    const sent = await run({ workspaceId: "w1", agentId: "antigravity-cli" });
    const done = sent.at(-1);
    assert.equal(done.type, "create_herdr_agent_done", "creation replies");
    assert.equal(done.ok, true, "creation succeeds");
    assert.equal(done.agent, "antigravity-cli", "the reply keeps the Nexus id");
    assert.equal(done.kind, "agy", "the reply exposes the resolved Herdr kind");
    const started = starts.at(-1);
    assert(started, "agent start was invoked");
    assert.equal(started.kind, "agy", "agent start received the Herdr kind, not the Nexus id");
    assert.notEqual(started.kind, "antigravity-cli", "the Nexus id is never sent to Herdr");
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

  // 4. A failed start closes the pane it created.
  {
    const closed = [];
    const sent = await run(
      { workspaceId: "w1", agentId: "cursor" },
      {
        startAgent: async () => { throw new Error("agent_pane_busy"); },
        closePane: async (paneId) => { closed.push(paneId); },
      },
    );
    const done = sent.at(-1);
    assert.equal(done.ok, false, "a failed start reports failure");
    assert.deepEqual(closed, ["w1:pNEW"], "the pane created for the failed start is closed");
  }

  // 5. A falsy start result is treated as failure and also releases the pane.
  {
    const closed = [];
    const sent = await run(
      { workspaceId: "w1", agentId: "cursor" },
      {
        startAgent: async () => false,
        closePane: async (paneId) => { closed.push(paneId); },
      },
    );
    assert.equal(sent.at(-1).ok, false, "a falsy start result fails");
    assert.deepEqual(closed, ["w1:pNEW"], "a falsy start result still releases the pane");
  }
} finally {
  HerdrAdapter.splitPane = originals.splitPane;
  HerdrAdapter.createTab = originals.createTab;
  HerdrAdapter.startAgent = originals.startAgent;
  HerdrAdapter.closePane = originals.closePane;
  if (previousStoreDir === undefined) delete process.env.NEXUS_AGENTS_STORE_DIR;
  else process.env.NEXUS_AGENTS_STORE_DIR = previousStoreDir;
  rmSync(storeDir, { recursive: true, force: true });
}

console.log("ALL AGENT KIND MAPPING TESTS PASSED!");
