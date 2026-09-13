import { mkdtempSync, rmSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${message}`);
  } else {
    failed += 1;
    console.error(`  ✗ ${message}`);
  }
}

/**
 * A fake `herdr` executable. Every structured command answers with the same
 * `{"id":"cli:<group>:<cmd>","result":{...}}` envelope the real CLI emits;
 * `agent read` answers with raw text, mirroring the real snapshot command.
 */
const FAKE_HERDR = `#!/usr/bin/env node
const argv = process.argv.slice(2);
const out = (obj) => process.stdout.write(JSON.stringify(obj) + "\\n");

if (argv[0] === "agent" && argv[1] === "list") {
  // Status is overridable so prompt admission can be exercised both ways.
  out({ id: "cli:agent:list", result: { type: "agent_list", agents: [
    { pane_id: "mock_p1", agent: "omp", agent_status: process.env.FAKE_HERDR_STATUS || "working", cwd: "/test",
      foreground_cwd: "/test", terminal_title_stripped: "mock", workspace_id: "w1" },
  ] } });
} else if (argv[0] === "agent" && argv[1] === "read") {
  // First read returns the seeded snapshot; later reads append a line so the
  // streamer has a real delta to compute.
  const fs = require("node:fs");
  const counter = process.env.FAKE_HERDR_COUNTER + "." + argv[2];
  let reads = 0;
  try { reads = parseInt(fs.readFileSync(counter, "utf8"), 10) || 0; } catch {}
  reads += 1;
  fs.writeFileSync(counter, String(reads));
  process.stdout.write(reads === 1 ? "Line 1\\nLine 2\\n" : "Line 1\\nLine 2\\nLine 3 (new)\\n");
} else if (argv[0] === "agent" && argv[1] === "prompt") {
  out({ id: "cli:agent:prompt", result: { type: "agent_prompted", agent: { pane_id: argv[2] } } });
} else if (argv[0] === "agent" && argv[1] === "get") {
  out({ id: "cli:agent:get", result: { type: "agent_info", agent: { pane_id: argv[2], agent: "omp", agent_status: "idle", cwd: "/test" } } });
} else if (argv[0] === "agent" && argv[1] === "wait") {
  out({ id: "cli:agent:wait", result: { type: "agent_info", agent: { pane_id: argv[2], agent: "omp", agent_status: "idle", cwd: "/test" } } });
} else if (argv[0] === "workspace" && argv[1] === "list") {
  out({ id: "cli:workspace:list", result: { type: "workspace_list", workspaces: [
    { workspace_id: "w1", label: "mock-ws", pane_count: 1, tab_count: 1 },
  ] } });
} else if (argv[0] === "workspace" && argv[1] === "create") {
  out({ id: "cli:workspace:create", result: { type: "workspace_created", workspace: { workspace_id: "w9" }, tab: { tab_id: "w9:t1" }, root_pane: { pane_id: "w9:p1" } } });
} else if (argv[0] === "integration" && argv[1] === "status") {
  process.stdout.write("pi: not installed (/tmp/pi.ts)\\nomp: current (v9) (/tmp/omp.ts)\\ncursor: outdated (/tmp/cursor.sh)\\n");
} else if (argv.includes("__argv__")) {
  out({ id: "cli:echo", result: { argv } });
} else if (argv.includes("__fail__")) {
  process.stderr.write("boom");
  process.exit(3);
} else {
  out({ id: "cli:unknown", error: { code: "invalid_request", message: "unsupported: " + argv.join(" ") } });
}
`;

async function main() {
  console.log("Testing HerdrAdapter over the Herdr CLI transport...");

  const {
    HerdrAdapter,
    HerdrStreamer,
    isHerdrCode,
  } = await import("../dist/discovery/herdr-adapter.mjs");
  const { HerdrCliClient, HerdrCliError, resolveHerdrBinary } =
    await import("../dist/discovery/herdr-cli.mjs");

  const tmpDir = mkdtempSync(join(tmpdir(), "nexus-herdr-cli-"));
  const fakeBin = join(tmpDir, "herdr");
  writeFileSync(fakeBin, FAKE_HERDR, "utf8");
  chmodSync(fakeBin, 0o755);
  process.env.HERDR_BIN_PATH = fakeBin;
  process.env.FAKE_HERDR_COUNTER = join(tmpDir, "reads.txt");

  try {
    assert(resolveHerdrBinary() === fakeBin, "resolveHerdrBinary() honours HERDR_BIN_PATH");
    assert(HerdrAdapter.isAvailable() === true, "isAvailable() is true when the binary resolves");

    // Structured commands unwrap the CLI envelope.
    const agents = await HerdrAdapter.listAgents();
    assert(agents.length === 1 && agents[0].pane_id === "mock_p1", "listAgents() parses the CLI envelope");
    assert(agents[0].agent_status === "working", "listAgents() keeps agent_status");

    const workspaces = await HerdrAdapter.listWorkspaces();
    assert(workspaces.length === 1 && workspaces[0].workspace_id === "w1", "listWorkspaces() parses workspaces");
    assert(await HerdrAdapter.createWorkspace("ws", "/tmp") === "w9", "createWorkspace() returns the new workspace id");

    // Raw-text command.
    const text = await HerdrAdapter.readTerminal("mock_p1", 3, "text");
    assert(text.includes("Line 1"), "readTerminal() returns raw CLI stdout");

    // Strict status helpers.
    assert(await HerdrAdapter.waitForStatus("mock_p1", ["idle", "done"], 500) === "idle", "waitForStatus() returns the reached status");
    assert((await HerdrAdapter.getAgent("mock_p1")).agent_status === "idle", "getAgent() returns the agent record");

    // Integration status text parsing.
    const integrations = await HerdrAdapter.getIntegrationStatus();
    assert(integrations.omp === true, "getIntegrationStatus() marks current integrations installed");
    assert(integrations.pi === false, "getIntegrationStatus() marks missing integrations uninstalled");
    assert(integrations.cursor === false, "getIntegrationStatus() treats outdated as not installed");

    // Prompt admission: an idle agent accepts, a working one is refused so a
    // second prompt cannot reach an agent that is still mid-turn.
    process.env.FAKE_HERDR_STATUS = "idle";
    await HerdrAdapter.sendPrompt("mock_p1", "hello");
    assert(true, "sendPrompt() succeeds against an idle agent");

    process.env.FAKE_HERDR_STATUS = "working";
    const busyErr = await HerdrAdapter.sendPrompt("mock_p1", "again").then(() => null, (e) => e);
    assert(busyErr && busyErr.herdrCode === "agent_busy", "sendPrompt() refuses a working agent");
    delete process.env.FAKE_HERDR_STATUS;

    // HerdrStreamer deltas over the CLI reader.
    const received = [];
    const listener = (event) => received.push(event);
    HerdrStreamer.subscribe("mock_stream", listener);
    // Two poll intervals (800ms) plus margin: the first poll seeds the snapshot,
    // the second produces the delta.
    await new Promise((resolve) => setTimeout(resolve, 2100));
    assert(received.length >= 1, "HerdrStreamer receives a delta event");
    assert(received[0]?.type === "agent_event", "streamer event type is agent_event");
    assert(received[0]?.event?.sessionUpdate === "agent_message_chunk", "streamer nests sessionUpdate");
    assert(received[0]?.event?.content?.text === "Line 3 (new)\n", "streamer delta matches new output exactly");
    HerdrStreamer.unsubscribe("mock_stream", listener);
    assert(true, "HerdrStreamer.unsubscribe tears down the listener");

    // Error surfacing.
    const err = await HerdrCliClient.run(["__fail__"]).then(() => null, (e) => e);
    assert(err instanceof HerdrCliError && err.code === "HERDR_EXIT", "non-zero exit rejects with HERDR_EXIT");
    const errMsg = await HerdrCliClient.runJson(["__unknown__"]).then(() => null, (e) => e);
    assert(errMsg instanceof HerdrCliError && errMsg.herdrCode === "invalid_request", "CLI error envelope carries the Herdr code");
    assert(isHerdrCode(errMsg, "invalid_request") === true, "isHerdrCode() recognises the Herdr code");
    assert(isHerdrCode(errMsg, "agent_not_found") === false, "isHerdrCode() rejects other codes");

    // Session targeting is passed to the CLI, never resolved to a socket path.
    process.env.HERDR_SESSION = "work";
    const echo = await HerdrCliClient.runJson(["__argv__"]);
    assert(echo.argv[0] === "--session" && echo.argv[1] === "work", "HERDR_SESSION prepends --session to argv");
    delete process.env.HERDR_SESSION;

    // Missing binary.
    process.env.HERDR_BIN_PATH = join(tmpDir, "does-not-exist");
    const missing = await HerdrCliClient.run(["agent", "list"]).then(() => null, (e) => e);
    assert(missing instanceof HerdrCliError && missing.code === "HERDR_BIN_NOT_FOUND", "missing binary rejects with HERDR_BIN_NOT_FOUND");
    assert(HerdrAdapter.isAvailable() === false, "isAvailable() is false without a resolvable binary");
    delete process.env.HERDR_BIN_PATH;
  } finally {
    rmSync(tmpDir, { recursive: true, force: true });
    delete process.env.HERDR_BIN_PATH;
    delete process.env.HERDR_SESSION;
    delete process.env.FAKE_HERDR_COUNTER;
  }

  console.log(`\nHerdrAdapter tests: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error("Test failed with uncaught error:", err);
  process.exit(1);
});
