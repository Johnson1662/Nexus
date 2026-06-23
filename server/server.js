const { WebSocketServer } = require("ws");
const { spawn, execSync } = require("child_process");
const fs = require("fs");
const path = require("path");
const os = require("os");

function expandCwd(cwd) {
  if (!cwd) return process.cwd();
  let expanded = cwd.trim();
  if (expanded.startsWith("~")) {
    expanded = path.join(os.homedir(), expanded.slice(1));
  }
  return path.resolve(expanded);
}

const PORT = 12138;

const wss = new WebSocketServer({ port: PORT });
console.log(`[server] listening on port ${PORT} (IPv4+IPv6)`);

// active ACP agent sessions: sessionId -> { process, ws, acpSessionId, pendingPermission }
const sessions = new Map();

// ── ACP Agent Registry ──
// Each entry: [binary_name_to_find_in_PATH, display_title]
const ACP_AGENTS = [
  ["opencode", "OpenCode"],
  ["claude-code", "Claude Code"],
  ["claude", "Claude Code"],
  ["gemini", "Gemini CLI"],
  ["claude", "Claude Code"],
  ["cline", "Cline"],
  ["kimi", "Kimi CLI"],
  ["qwen-code", "Qwen Code"],
  ["mistral-vibe", "Mistral Vibe"],
  ["goose", "Goose"],
  ["minion-code", "Minion Code"],
  ["openclaw", "OpenClaw"],
  ["qoder", "Qoder CLI"],
  ["vtcode", "VT Code"],
  ["crow", "crow-cli"],
  ["code-assistant", "Code Assistant"],
  ["stakpak", "Stakpak"],
  ["poolside", "Poolside"],
  ["cursor", "Cursor"],
  ["augment-code", "Augment Code"],
  ["blackbox", "Blackbox AI"],
  ["fast-agent", "fast-agent"],
  ["fount", "fount"],
  ["hermes", "Hermes Agent"],
  ["kiro", "Kiro CLI"],
  ["kiro-cli", "Kiro CLI"],
  ["junie", "Junie"],
  ["copilot", "GitHub Copilot"],
  ["docker-cagent", "Docker cagent"],
  ["pi", "pi coding agent"],
  ["factory-droid", "Factory Droid"],
  ["openhands", "OpenHands"],
  ["agoragentic", "Agoragentic"],
  ["amp", "Amp"],
  ["autohand-code", "Autohand Code"],
  ["codebuddy", "Codebuddy Code"],
  ["cortex-code", "Cortex Code"],
  ["corust", "Corust Agent"],
  ["deepagents", "DeepAgents"],
  ["dimcode", "DimCode"],
  ["dirac", "Dirac"],
  ["kilo", "Kilo"],
  ["nova", "Nova"],
  ["sigit-code", "siGit Code"],
  ["glm-agent", "GLM Agent"],
  ["rayclaw", "RayClaw"],
  ["stdio-bus", "stdio Bus"],
  ["iflow-cli", "iflow-cli"],
  ["lody", "Lody"],
  ["toad", "Toad"],
  ["pixi", "pixi"],
  ["tidewave", "Tidewave"],
  ["mitto", "Mitto"],
  ["nori-cli", "Nori CLI"],
  ["ngent", "Ngent"],
  ["rlm-code", "RLM Code"],
  ["happy", "Happy"],
  ["jockey", "Jockey"],
  ["agente", "Agmente"],
  ["ferngeist", "Ferngeist"],
  ["mobvibe", "Mobvibe"],
  ["omp", "oh-my-pi"],
];

// ── ACP Agent Launch Args (from official registry) ──
const AGENT_LAUNCH_ARGS = {
  opencode: ["acp"],
  "claude-code": ["acp"],
  claude: ["acp"],
  gemini: ["--acp"],
  cline: ["--acp"],
  kimi: ["acp"],
  "qwen-code": ["--acp", "--experimental-skills"],
  "mistral-vibe": ["acp"],
  goose: ["acp"],
  "minion-code": ["acp"],
  openclaw: ["acp"],
  qoder: ["--acp"],
  vtcode: ["acp"],
  crow: ["acp"],
  codex: ["acp"],
  "codex-acp": [],
  "code-assistant": ["acp"],
  stakpak: ["acp"],
  poolside: ["acp"],
  cursor: ["acp"],
  "cursor-agent": ["acp"],
  auggie: ["--acp"],
  "augment-code": ["--acp"],
  blackbox: ["acp"],
  "fast-agent": ["acp"],
  fount: ["acp"],
  hermes: ["acp"],
  kiro: ["acp"],
  "kiro-cli": ["acp"],
  junie: ["--acp=true"],
  copilot: ["--acp"],
  "docker-cagent": ["acp"],
  pi: ["acp"],
  "pi-acp": [],
  "factory-droid": ["acp"],
  openhands: ["acp"],
  agoragentic: ["--acp"],
  amp: ["acp"],
  "amp-acp": [],
  "autohand-code": [],
  codebuddy: ["--acp"],
  "cortex-code": ["acp", "serve"],
  "corust-agent-acp": [],
  deepagents: [],
  dimcode: ["acp"],
  dirac: ["--acp"],
  kilo: ["acp"],
  nova: ["acp"],
  sigit: [],
  "sigit-code": [],
  "glm-agent": [],
  rayclaw: ["acp"],
  "stdio-bus": ["acp"],
  "iflow-cli": ["acp"],
  lody: ["acp"],
  toad: ["acp"],
  pixi: ["acp"],
  tidewave: ["acp"],
  mitto: ["acp"],
  "nori-cli": ["acp"],
  ngent: ["acp"],
  "rlm-code": ["acp"],
  happy: ["acp"],
  jockey: ["acp"],
  agente: ["acp"],
  ferngeist: ["acp"],
  mobvibe: ["acp"],
  omp: ["acp"],
};

function getAgentLaunchArgs(agentName) {
  return AGENT_LAUNCH_ARGS[agentName] || ["acp"];
}

// ── Agent config file location patterns ──
function getAgentConfigPaths(agentName, cwd) {
  const appData = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming");
  const home = os.homedir();
  const configs = {
    "opencode": [
      path.join(cwd || process.cwd(), ".commandcode", "mcp.json")
    ],
    "claude-code": [
      path.join(appData, "Claude", "claude_desktop_config.json"),
      path.join(appData, "Claude Code", "config.json"),
      path.join(home, ".claude", "claude_desktop_config.json")
    ],
    "cline": [
      path.join(appData, "Code - OSS", "User", "globalStorage", "saoudrizwan.claude-dev", "settings", "cline_mcp_settings.json"),
      path.join(appData, "Cursor", "User", "globalStorage", "saoudrizwan.claude-dev", "settings", "cline_mcp_settings.json"),
      path.join(appData, "Windsurf", "User", "globalStorage", "saoudrizwan.claude-dev", "settings", "cline_mcp_settings.json")
    ],
    "cursor": [
      path.join(cwd || process.cwd(), ".cursor", "mcp.json")
    ],
    "goose": [
      path.join(home, ".config", "goose", "config.yaml"),
      path.join(home, ".config", "goose", "config.json")
    ]
  };
  return configs[agentName] || [];
}

// ── Agent binary discovery in PATH ──
function findInPath(binaryName) {
  const pathDirs = (process.env.PATH || "").split(path.delimiter);
  const extensions = [".cmd", ".exe", ".bat", ".ps1", ""];
  for (const dir of pathDirs) {
    if (!dir) continue;
    for (const ext of extensions) {
      const fullPath = path.join(dir.trim(), binaryName + ext);
      try {
        if (fs.existsSync(fullPath)) {
          return fullPath;
        }
      } catch {}
    }
  }
  return null;
}

// Try to get version from binary
function getAgentVersion(binaryPath) {
  // Try --version first, fall back to --help (some agents only support one or the other)
  const commands = ["--version", "--help"];
  for (const cmd of commands) {
    try {
      const result = execSync(`"${binaryPath}" ${cmd}`, { encoding: "utf8", timeout: 3000 });
      return result.trim().split("\n")[0];
    } catch {
      // try next command
    }
  }
  return null;
}

// ── Agent binary discovery in PATH ──
function findInPath(binaryName) {
  const pathDirs = (process.env.PATH || "").split(path.delimiter);
  const extensions = [".cmd", ".exe", ".bat", ".ps1", ""];
  for (const dir of pathDirs) {
    if (!dir) continue;
    for (const ext of extensions) {
      const fullPath = path.join(dir.trim(), binaryName + ext);
      try {
        if (fs.existsSync(fullPath)) {
          return fullPath;
        }
      } catch {}
    }
  }
  return null;
}

// Try to get version from binary
function getAgentVersion(binaryPath) {
  // Try --version first, fall back to --help (some agents only support one or the other)
  const commands = ["--version", "--help"];
  for (const cmd of commands) {
    try {
      const result = execSync(`"${binaryPath}" ${cmd}`, { encoding: "utf8", timeout: 3000 });
      return result.trim().split("\n")[0];
    } catch {
      // try next command
    }
  }
  return null;
}

// ── Agent discovery: scan PATH for each known ACP agent ──
function discoverAgents() {
  const discovered = [];
  for (const [binaryName, title] of ACP_AGENTS) {
    const binaryPath = findInPath(binaryName);
    if (binaryPath) {
      const version = getAgentVersion(binaryPath);
      discovered.push({
        name: binaryName,
        title,
        version: version || "unknown",
        source: "path",
        binaryPath,
        installed: true
      });
    }
  }
  console.log(`[server] discovered ${discovered.length} ACP agents: ${discovered.map(a => a.name).join(", ")}`);
  return discovered;
}

// ── Load MCP config for a specific agent ──
function loadMcpConfigForAgent(agentName, cwd) {
  const configPaths = getAgentConfigPaths(agentName, cwd);

  // First check agent-specific paths
  for (const configPath of configPaths) {
    try {
      if (fs.existsSync(configPath)) {
        const raw = JSON.parse(fs.readFileSync(configPath, "utf-8"));
        const servers = raw.mcpServers || raw.mcpServers || {};
        return parseMcpServers(servers);
      }
    } catch {}
  }

  // Fall back to the generic .commandcode/mcp.json
  try {
    const fallbackPath = path.join(cwd || process.cwd(), ".commandcode", "mcp.json");
    if (fs.existsSync(fallbackPath)) {
      const raw = JSON.parse(fs.readFileSync(fallbackPath, "utf-8"));
      return parseMcpServers(raw.mcpServers || raw.mcpServers || {});
    }
  } catch {}

  return [];
}

function parseMcpServers(servers) {
  return Object.entries(servers)
    .filter(([, s]) => s.enabled !== false)
    .map(([name, s]) => {
      if (s.transport === "http" || s.transport === "sse") {
        return {
          name,
          type: s.transport,
          url: s.url,
          headers: Object.entries(s.headers || {}).map(([k, v]) => ({ name: k, value: String(v) }))
        };
      } else {
        return {
          name,
          type: "stdio",
          command: s.command,
          args: s.args || [],
          env: Object.entries(s.env || {}).map(([k, v]) => ({ name: k, value: String(v) }))
        };
      }
    });
}

wss.on("connection", (ws) => {
  console.log("[server] client connected");

  // Send server info immediately on connect
  try {
    const hostname = os.hostname();
    const nets = os.networkInterfaces();
    const ips = [];
    for (const name of Object.keys(nets)) {
      for (const net of nets[name]) {
        if (!net.internal) {
          ips.push(net.address);
        }
      }
    }
    ws.send(JSON.stringify({ type: "server_info", hostname, ips }));
    console.log(`[server] sent server_info: ${hostname} (${ips.length} IPs)`);
  } catch (err) {
    console.log(`[server] failed to get host info: ${err}`);
  }

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString());
    } catch {
      ws.send(JSON.stringify({ type: "error", text: "invalid json" }));
      return;
    }

    if (msg.type === "start") {
      handleStart(ws, msg).catch((err) => {
        console.log(`[server] handleStart error: ${err.message}`);
      });
    } else if (msg.type === "list_agents") {
      handleListAgents(ws, msg);
    } else if (msg.type === "input") {
      handleInput(ws, msg);
    } else if (msg.type === "cancel") {
      handleCancel(ws, msg);
    } else if (msg.type === "switch_model") {
      handleSwitchModel(ws, msg).catch((err) => {
        console.log(`[server] handleSwitchModel error: ${err.message}`);
      });
    } else if (msg.type === "list_models") {
      handleListModels(ws, msg).catch((err) => {
        console.log(`[server] handleListModels error: ${err.message}`);
      });
    } else if (msg.type === "list_sessions") {
      handleListSessions(ws, msg).catch((err) => {
        console.log(`[server] handleListSessions error: ${err.message}`);
      });
    } else if (msg.type === "set_mode") {
      handleSetMode(ws, msg).catch((err) => {
        console.log(`[server] handleSetMode error: ${err.message}`);
      });
    } else if (msg.type === "load_session") {
      handleLoadSession(ws, msg).catch((err) => {
        console.log(`[server] handleLoadSession error: ${err.message}`);
      });
    } else if (msg.type === "permission_response") {
      handlePermissionResponse(ws, msg);
    }
  });

  ws.on("close", () => {
    console.log("[server] client disconnected, cleaning up sessions");
    sessionListCache.delete(ws);
    for (const [id, sess] of sessions) {
      if (sess.ws === ws) {
        killSession(sess);
        sessions.delete(id);
      }
    }
  });
});

// ── JSON-RPC helpers ──

let nextRpcId = 1;
const pendingRequests = new Map(); // rpcId -> { resolve, reject }

function sendRpc(proc, method, params) {
  return new Promise((resolve, reject) => {
    const id = nextRpcId++;
    pendingRequests.set(id, { resolve, reject, proc });
    const msg = JSON.stringify({ jsonrpc: "2.0", id, method, params });
    console.log(`[ACP →] ${msg}`);
    proc.stdin.write(msg + "\n");
  });
}

function sendNotification(proc, method, params) {
  const msg = JSON.stringify({ jsonrpc: "2.0", method, params });
  console.log(`[ACP →] ${msg.slice(0, 200)}`);
  proc.stdin.write(msg + "\n");
}

function handleAcpMessage(sess, line) {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    console.log(`[ACP ←] non-JSON: ${line.slice(0, 100)}`);
    return;
  }

  if (line.includes("availableModels") || line.includes("availableCommands")) {
    console.log(`[ACP ←] ${line.slice(0, 300)}…`);
  } else {
    console.log(`[ACP ←] ${line}`);
  }

  // Response to our request — match proc to prevent cross‑session ID collisions
  if (msg.id !== undefined && pendingRequests.has(msg.id)) {
    const pending = pendingRequests.get(msg.id);
    if (pending.proc !== sess.process) {
      return;
    }
    pendingRequests.delete(msg.id);
    if (msg.error) {
      pending.reject(new Error(msg.error.message || JSON.stringify(msg.error)));
    } else {
      pending.resolve(msg.result);
    }
    return;
  }

  // Request FROM agent (has method + id) - need to respond
  if (msg.method && msg.id !== undefined) {
    handleAgentRequest(sess, msg);
    return;
  }

  // Notification from agent (has method, no id)
  if (msg.method) {
    handleAcpNotification(sess, msg.method, msg.params);
  }
}

function sendAcpResponse(proc, id, result) {
  const msg = JSON.stringify({ jsonrpc: "2.0", id, result });
  console.log(`[ACP →] ${msg.slice(0, 200)}`);
  proc.stdin.write(msg + "\n");
}

function sendAcpError(proc, id, code, message) {
  const msg = JSON.stringify({
    jsonrpc: "2.0",
    id,
    error: { code, message },
  });
  console.log(`[ACP →] ${msg.slice(0, 200)}`);
  proc.stdin.write(msg + "\n");
}

async function handleAcpNotification(sess, method, params) {
  const { ws, sessionId } = sess;

  if (method === "session/update") {
    ws.send(
      JSON.stringify({
        type: "agent_event",
        sessionId,
        event: params.update,
      })
    );
  } else {
    console.log(`[ACP] unknown notification: ${method}`);
  }
}

async function handleAgentRequest(sess, msg) {
  const { ws, sessionId, process: proc } = sess;
  const { method, params, id } = msg;

  if (method === "session/request_permission") {
    sess.pendingPermission = { id, params };
    ws.send(
      JSON.stringify({
        type: "permission_request",
        sessionId,
        requestId: params.requestId,
        toolCall: params.toolCall,
        options: params.options,
      })
    );
  } else {
    console.log(`[ACP] unknown request: ${method}`);
    sendAcpError(proc, id, -32601, `Method not found: ${method}`);
  }
}

function killSession(sess) {
  if (sess.process && !sess.process.killed) {
    try {
      sess.process.kill("SIGTERM");
    } catch {}
  }
}

function loadMcpConfig(cwd) {
  try {
    const fs = require("fs");
    const path = require("path");
    const configPath = path.join(cwd || process.cwd(), ".commandcode", "mcp.json");
    if (!fs.existsSync(configPath)) return [];
    const raw = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    const servers = raw.mcpServers || {};
    return Object.entries(servers)
      .filter(([, s]) => s.enabled !== false)
      .map(([name, s]) => {
        if (s.transport === "http" || s.transport === "sse") {
          return {
            name,
            type: s.transport,
            url: s.url,
            headers: Object.entries(s.headers || {}).map(([k, v]) => ({ name: k, value: String(v) }))
          };
        } else {
          return {
            name,
            type: "stdio",
            command: s.command,
            args: s.args || [],
            env: Object.entries(s.env || {}).map(([k, v]) => ({ name: k, value: String(v) }))
          };
        }
      });
  } catch (err) {
    console.log(`[server] loadMcpConfig error: ${err.message}`);
    return [];
  }
}

function findSessionForWs(ws) {
  for (const [, sess] of sessions) {
    if (sess.ws === ws && sess.acpSessionId) {
      return sess;
    }
  }
  return null;
}

// ── Handlers ──

function handleListAgents(ws, msg) {
  console.log("[server] discovering ACP agents...");
  try {
    const agents = discoverAgents();
    ws.send(JSON.stringify({ type: "agent_list", agents }));
  } catch (err) {
    console.log(`[server] agent discovery error: ${err.message}`);
    ws.send(JSON.stringify({ type: "agent_list", agents: [] }));
  }
}

const DEFAULT_MODEL = "opencode/minimax-m2.5-free";

async function handleStart(ws, msg) {
  const { agent = "opencode", prompt, cwd: rawCwd, model } = msg;
  const cwd = expandCwd(rawCwd);

  // ACP is agent-agnostic — accept any agent type
  console.log(`[server] starting agent: ${agent}`);

  const effectiveModel = model || DEFAULT_MODEL;

  // Since we are running on Windows, cross-platform spawning requires setting shell: true
  // to resolve the global executable (e.g., 'opencode.cmd') automatically from PATH.
  const args = getAgentLaunchArgs(agent);
  
  const proc = spawn(agent, args, {
    cwd,
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    shell: true 
  });

  const sessionId = `acp-${Date.now()}`;
  const sess = { process: proc, ws, sessionId, pendingPermission: null, acpSessionId: null };
  sessions.set(sessionId, sess);

  // Buffer for incomplete lines from stdout
  let stdoutBuffer = "";
  proc.stdout.on("data", (chunk) => {
    stdoutBuffer += chunk.toString();
    const lines = stdoutBuffer.split("\n");
    stdoutBuffer = lines.pop();
    for (const line of lines) {
      handleAcpMessage(sess, line);
    }
  });

  proc.stderr.on("data", (chunk) => {
    const text = chunk.toString();
    console.log(`[server] stderr: ${text.slice(0, 200)}`);
    ws.send(JSON.stringify({ type: "agent_stderr", sessionId, text }));
  });

  proc.on("error", (err) => {
    console.log(`[server] ${sessionId} spawn error: ${err.message}`);
    ws.send(
      JSON.stringify({ type: "error", text: `spawn failed: ${err.message}` })
    );
    sessions.delete(sessionId);
  });

  proc.on("exit", (code) => {
    console.log(`[server] ${sessionId} exited with code ${code}`);
    ws.send(
      JSON.stringify({ type: "session_ended", sessionId, exitCode: code })
    );
    sessions.delete(sessionId);
  });

  try {
    // Initialize ACP connection
    console.log(`[server] initializing ACP for ${sessionId}...`);
    const initResult = await sendRpc(proc, "initialize", {
      protocolVersion: 1,
      clientCapabilities: {
        fs: { readTextFile: true, writeTextFile: true },
        terminal: true,
      },
      clientInfo: { name: agent, title: "Anywhere Bridge", version: "0.2.0" },
    });
    console.log(`[server] ACP initialized, agent: ${initResult?.agentInfo?.name}`);

    // Create session WITHOUT MCP servers (fast path - MCP loads in background later)
    const sessionResult = await sendRpc(proc, "session/new", {
      cwd,
      mcpServers: [],
    });
    const acpSessionId = sessionResult.sessionId;
    sess.acpSessionId = acpSessionId;
    console.log(`[server] ACP session created: ${acpSessionId}`);

    // Set model
    console.log(`[server] setting model to ${effectiveModel}`);
    await sendRpc(proc, "session/set_model", {
      sessionId: acpSessionId,
      modelId: effectiveModel,
    });

    const models = (sessionResult.models?.availableModels || []).map((m) => ({
      modelId: m.modelId,
      name: m.name,
    }));
    const modes = (sessionResult.modes?.availableModes || []).map((m) => ({
      value: m.id,
      name: m.name,
    }));
    ws.send(JSON.stringify({ type: "model_list", models, modes }));

    // Notify client immediately (don't wait for MCP)
    ws.send(
      JSON.stringify({
        type: "session_started",
        sessionId,
        agent: agent,
        prompt,
        acpSessionId,
        model: effectiveModel,
      })
    );

    // Load MCP config in background (non-blocking)
    const mcpServers = loadMcpConfigForAgent(agent, cwd);
    if (mcpServers.length > 0) {
      console.log(`[server] loaded ${mcpServers.length} MCP servers for ${agent}, connecting in background...`);
      // Try to reconnect MCP by updating the session (best-effort, non-blocking)
      sendRpc(proc, "session/set_config_option", {
        sessionId: acpSessionId,
        configId: "_mcp_servers",
        value: JSON.stringify(mcpServers),
      }).catch(() => {
        // MCP setup is best-effort, ignore errors
      });
    }

    // If prompt provided, send it
    if (prompt) {
      sendRpc(proc, "session/prompt", {
        sessionId: acpSessionId,
        prompt: [{ type: "text", text: prompt }],
      }).then((result) => {
        // Turn ended - notify client
        console.log(`[server] turn ended: ${result?.stopReason}`);
        ws.send(
          JSON.stringify({
            type: "turn_ended",
            sessionId,
            stopReason: result?.stopReason,
          })
        );
      }).catch((err) => {
        console.log(`[server] prompt error: ${err.message}`);
        ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
        ws.send(JSON.stringify({ type: "error", sessionId, text: `Agent error: ${err.message}` }));
      });
    }
  } catch (err) {
    console.log(`[server] ACP init error: ${err.message}`);
    ws.send(
      JSON.stringify({
        type: "error",
        text: `ACP initialization failed: ${err.message}`,
      })
    );
    killSession(sess);
    sessions.delete(sessionId);
  }
}

function handleInput(ws, msg) {
  const { sessionId, text } = msg;
  const sess = sessions.get(sessionId);
  if (!sess || !sess.acpSessionId) {
    ws.send(JSON.stringify({ type: "error", text: `no active session: ${sessionId}` }));
    return;
  }

  const acpPrompt = {
    sessionId: sess.acpSessionId,
    prompt: [{ type: "text", text }],
  };

  sendRpc(sess.process, "session/prompt", acpPrompt)
    .then((result) => {
      // Turn ended - notify client
      console.log(`[server] turn ended: ${result?.stopReason}`);
      ws.send(
        JSON.stringify({
          type: "turn_ended",
          sessionId,
          stopReason: result?.stopReason,
        })
      );
    })
    .catch((err) => {
      console.log(`[server] prompt error: ${err.message}`);
      ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
      ws.send(JSON.stringify({ type: "error", sessionId, text: `Agent error: ${err.message}` }));
    });
}

function handleCancel(ws, msg) {
  const { sessionId } = msg;
  const sess = sessions.get(sessionId);
  if (!sess) return;

  sendNotification(sess.process, "session/cancel", {
    sessionId: sess.acpSessionId,
  });
  ws.send(JSON.stringify({ type: "session_cancelled", sessionId }));
}

async function handleListModels(ws, msg) {
  const sess = findSessionForWs(ws);
  if (!sess) {
    ws.send(JSON.stringify({ type: "model_list", models: [] }));
    return;
  }

  try {
    const result = await sendRpc(sess.process, "session/new", {
      cwd: process.cwd(),
      mcpServers: loadMcpConfig(),
    });
    const models = (result.models?.availableModels || []).map((m) => ({
      modelId: m.modelId,
      name: m.name,
    }));
    const modes = (result.modes?.availableModes || []).map((m) => ({
      value: m.id,
      name: m.name,
    }));
    console.log(`[server] list_models: ${models.length} models, ${modes.length} modes`);
    ws.send(JSON.stringify({ type: "model_list", models, modes }));
  } catch (err) {
    console.log(`[server] list_models error: ${err.message}`);
    ws.send(JSON.stringify({ type: "model_list", models: [] }));
  }
}

// ── Session list cache ──
const sessionListCache = new Map(); // ws -> { sessions, timestamp }

async function handleListSessions(ws, msg) {
  const cwd = msg.cwd ? expandCwd(msg.cwd) : undefined;
  const sess = findSessionForWs(ws);
  if (!sess) {
    ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
    return;
  }

  // Check cache (valid for 30 seconds)
  const cached = sessionListCache.get(ws);
  if (cached && Date.now() - cached.timestamp < 30000) {
    ws.send(JSON.stringify({ type: "session_list", sessions: cached.sessions }));
    return;
  }

  // Return empty immediately, fetch in background
  ws.send(JSON.stringify({ type: "session_list", sessions: [] }));

  try {
    const result = await sendRpc(sess.process, "session/list", {
      cwd: cwd || undefined,
    });
    const sessions = result.sessions || [];
    sessionListCache.set(ws, { sessions, timestamp: Date.now() });
    ws.send(JSON.stringify({ type: "session_list", sessions }));
  } catch (err) {
    console.log(`[server] list_sessions error: ${err.message}`);
  }
}

async function handleSetMode(ws, msg) {
  const { sessionId, modeId } = msg;
  const sess = sessions.get(sessionId);
  if (!sess || !sess.acpSessionId) {
    ws.send(JSON.stringify({ type: "error", text: "no active session" }));
    return;
  }
  try {
    await sendRpc(sess.process, "session/set_mode", {
      sessionId: sess.acpSessionId,
      modeId: modeId,
    });
    ws.send(JSON.stringify({ type: "mode_set", sessionId, modeId }));
  } catch (err) {
    ws.send(JSON.stringify({ type: "error", text: `set_mode failed: ${err.message}` }));
  }
}

async function handleSwitchModel(ws, msg) {
  const { sessionId, model } = msg;
  const sess = sessions.get(sessionId);
  if (!sess || !sess.acpSessionId) {
    ws.send(JSON.stringify({ type: "error", text: `no active session: ${sessionId}` }));
    return;
  }

  if (!model) {
    ws.send(JSON.stringify({ type: "error", text: "model is required" }));
    return;
  }

  const effectiveModel = model || DEFAULT_MODEL;

  try {
    console.log(`[server] switching model for ${sessionId} to ${effectiveModel}`);
    await sendRpc(sess.process, "session/set_model", {
      sessionId: sess.acpSessionId,
      modelId: effectiveModel,
    });
    console.log(`[server] model switched for ${sessionId} to ${effectiveModel}`);
    ws.send(
      JSON.stringify({
        type: "model_switched",
        sessionId,
        model: effectiveModel,
      })
    );
  } catch (err) {
    console.log(`[server] switch_model error: ${err.message}`);
    ws.send(
      JSON.stringify({ type: "error", text: `model switch failed: ${err.message}` })
    );
  }
}

async function handleLoadSession(ws, msg) {
  const { sessionId, cwd: rawCwd } = msg;
  const cwd = expandCwd(rawCwd);
  if (!sessionId) {
    ws.send(JSON.stringify({ type: "error", text: "sessionId is required" }));
    return;
  }

  // Kill old session for this WS
  for (const [id, sess] of sessions) {
    if (sess.ws === ws) {
      killSession(sess);
      sessions.delete(id);
    }
  }

  // Spawn agent process (same as handleStart)
  const agent = msg.agent || "opencode";
  const args = getAgentLaunchArgs(agent);
  const proc = spawn(agent, args, {
    cwd,
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    shell: true,
  });

  const bridgeSessionId = `acp-${Date.now()}`;
  const sess = { process: proc, ws, sessionId: bridgeSessionId, pendingPermission: null, acpSessionId: null };
  sessions.set(bridgeSessionId, sess);

  let stdoutBuffer = "";
  proc.stdout.on("data", (chunk) => {
    stdoutBuffer += chunk.toString();
    const lines = stdoutBuffer.split("\n");
    stdoutBuffer = lines.pop();
    for (const line of lines) {
      handleAcpMessage(sess, line);
    }
  });

  proc.stderr.on("data", (chunk) => {
    console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    ws.send(JSON.stringify({ type: "agent_stderr", sessionId: bridgeSessionId, text: chunk.toString() }));
  });

  proc.on("error", (err) => {
    console.log(`[server] ${bridgeSessionId} spawn error: ${err.message}`);
    sessions.delete(bridgeSessionId);
  });

  proc.on("exit", (code) => {
    console.log(`[server] ${bridgeSessionId} exited with code ${code}`);
    sessions.delete(bridgeSessionId);
  });

  try {
    console.log(`[server] initializing ACP for load session ${sessionId}...`);
    await sendRpc(proc, "initialize", {
      protocolVersion: 1,
      clientCapabilities: {
        fs: { readTextFile: true, writeTextFile: true },
        terminal: true,
      },
      clientInfo: { name: msg.agent || "opencode", title: "Anywhere Bridge", version: "0.2.0" },
    });

    console.log(`[server] loading session ${sessionId}`);
    await sendRpc(proc, "session/load", {
      sessionId: sessionId,
      cwd,
      mcpServers: loadMcpConfig(cwd),
    });

    // Set model after load
    if (msg.model) {
      await sendRpc(proc, "session/set_model", {
        sessionId: sessionId,
        modelId: msg.model,
      }).catch(() => {});
    }

    ws.send(JSON.stringify({
      type: "session_started",
      sessionId: bridgeSessionId,
      agent: msg.agent || "opencode",
      loadedSessionId: sessionId,
    }));
  } catch (err) {
    console.log(`[server] load_session error: ${err.message}`);
    ws.send(JSON.stringify({ type: "error", text: `load session failed: ${err.message}` }));
    killSession(sess);
    sessions.delete(bridgeSessionId);
  }
}

function handlePermissionResponse(ws, msg) {
  const { sessionId, requestId, outcome } = msg;
  const sess = sessions.get(sessionId);
  if (!sess || !sess.pendingPermission) {
    ws.send(JSON.stringify({ type: "error", text: "no pending permission request" }));
    return;
  }

  const { id: rpcId } = sess.pendingPermission;
  sess.pendingPermission = null;

  const validOutcomes = ["allow", "deny", "selected"];
  if (!validOutcomes.includes(outcome)) {
    sendAcpError(sess.process, rpcId, -32602, `Invalid outcome: ${outcome}`);
    return;
  }

  sendAcpResponse(sess.process, rpcId, { outcome });
}
