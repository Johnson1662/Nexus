import { mkdtempSync, rmSync, writeFileSync, chmodSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * Fake `herdr` executable for tests.
 *
 * The transport is the Herdr CLI, so tests script a stand-in binary instead of
 * a mock socket server. Behaviour is driven by two files the test owns:
 *
 *  - `state`  (JSON, rewritten by the test): `{ agents, readText, status,
 *    errors: { "<group> <cmd>": "herdr_error_code" } }`
 *  - `log`    (JSONL, appended by the fake): every argv it was invoked with
 *
 * `status` overrides each agent's `agent_status`, which is how the cancel
 * lifecycle tests flip an agent from working to idle.
 */
export function createFakeHerdr() {
  const dir = mkdtempSync(join(tmpdir(), "nexus-fake-herdr-"));
  const bin = join(dir, "herdr");
  const statePath = join(dir, "state.json");
  const logPath = join(dir, "calls.jsonl");

  writeFileSync(statePath, JSON.stringify({ agents: [], readText: "" }), "utf8");
  writeFileSync(logPath, "", "utf8");

  writeFileSync(bin, `#!/usr/bin/env node
const fs = require("node:fs");
let argv = process.argv.slice(2);
if (argv[0] === "--session") argv = argv.slice(2);
const log = process.env.FAKE_HERDR_LOG;
if (log) fs.appendFileSync(log, JSON.stringify(argv) + "\\n");
let state = {};
try { state = JSON.parse(fs.readFileSync(process.env.FAKE_HERDR_STATE, "utf8")); } catch {}
const out = (o) => process.stdout.write(JSON.stringify(o) + "\\n");
const group = argv[0], cmd = argv[1];
const fail = (state.errors || {})[group + " " + cmd];
if (fail) { out({ id: "cli:" + group + ":" + cmd, error: { code: fail, message: group + "." + cmd + " failed" } }); process.exit(1); }
const agents = () => (state.agents || []).map((a) => Object.assign({}, a, state.status ? { agent_status: state.status } : {}));
const paneId = argv[2];
if (group === "agent" && cmd === "list") out({ id: "cli:agent:list", result: { type: "agent_list", agents: agents() } });
else if (group === "agent" && cmd === "read") process.stdout.write(state.readText || "");
else if (group === "agent" && (cmd === "get" || cmd === "wait")) {
  const agent = agents().find((a) => a.pane_id === paneId);
  if (!agent) { out({ id: "cli:agent:" + cmd, error: { code: "agent_not_found", message: "agent target " + paneId + " not found" } }); process.exit(1); }
  out({ id: "cli:agent:" + cmd, result: { type: "agent_info", agent } });
}
else if (group === "agent" && cmd === "prompt") out({ id: "cli:agent:prompt", result: { type: "agent_prompted", agent: { pane_id: paneId } } });
else if (group === "agent" && cmd === "send-keys") out({ id: "cli:agent:send-keys", result: { type: "ok" } });
else if (group === "agent" && cmd === "start") out({ id: "cli:agent:start", result: { type: "agent_started", agent: { pane_id: paneId, agent: "mock", agent_status: "working", cwd: "/tmp" }, argv: [] } });
else if (group === "pane" && (cmd === "close" || cmd === "focus")) out({ id: "cli:pane:" + cmd, result: { type: "ok" } });
else if (group === "pane" && cmd === "split") out({ id: "cli:pane:split", result: { type: "pane_info", pane: { pane_id: "w1:p" + Math.floor(Math.random() * 1000) } } });
else if (group === "tab" && cmd === "create") out({ id: "cli:tab:create", result: { type: "tab_created", tab: { tab_id: "w1:t9" }, root_pane: { pane_id: "w1:p9" } } });
else if (group === "workspace" && cmd === "list") out({ id: "cli:workspace:list", result: { type: "workspace_list", workspaces: state.workspaces || [] } });
else if (group === "workspace" && cmd === "create") out({ id: "cli:workspace:create", result: { type: "workspace_created", workspace: { workspace_id: "w-new" }, tab: { tab_id: "w-new:t1" }, root_pane: { pane_id: "w-new:p1" } } });
else if (group === "workspace" && cmd === "focus") out({ id: "cli:workspace:focus", result: { type: "ok" } });
else if (group === "integration" && cmd === "status") process.stdout.write(state.integrationStatus || "");
else if (group === "integration" && cmd === "install") out({ id: "cli:integration:install", result: { type: "integration_install", target: argv[2], details: "" } });
else out({ id: "cli:unknown", error: { code: "invalid_request", message: "unsupported: " + argv.join(" ") } });
`, "utf8");
  chmodSync(bin, 0o755);

  const previous = {
    bin: process.env.HERDR_BIN_PATH,
    state: process.env.FAKE_HERDR_STATE,
    log: process.env.FAKE_HERDR_LOG,
    session: process.env.HERDR_SESSION,
  };
  process.env.HERDR_BIN_PATH = bin;
  process.env.FAKE_HERDR_STATE = statePath;
  process.env.FAKE_HERDR_LOG = logPath;
  delete process.env.HERDR_SESSION;

  return {
    bin,
    setState(patch) {
      const current = JSON.parse(readFileSync(statePath, "utf8"));
      writeFileSync(statePath, JSON.stringify({ ...current, ...patch }), "utf8");
    },
    calls() {
      return readFileSync(logPath, "utf8")
        .split("\n")
        .filter(Boolean)
        .map((line) => JSON.parse(line));
    },
    cleanup() {
      if (previous.bin === undefined) delete process.env.HERDR_BIN_PATH;
      else process.env.HERDR_BIN_PATH = previous.bin;
      if (previous.state === undefined) delete process.env.FAKE_HERDR_STATE;
      else process.env.FAKE_HERDR_STATE = previous.state;
      if (previous.log === undefined) delete process.env.FAKE_HERDR_LOG;
      else process.env.FAKE_HERDR_LOG = previous.log;
      if (previous.session !== undefined) process.env.HERDR_SESSION = previous.session;
      rmSync(dir, { recursive: true, force: true });
    },
  };
}
