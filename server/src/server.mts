import { WebSocketServer, type WebSocket } from "ws";
import http, { type IncomingMessage, type ServerResponse } from "node:http";
import os from "os";
import { getOrCreateHostId, getOrCreateHostIdentity } from "./host-identity.mjs";
// ── Protocol layering: transport vs session messages ──────────
//
// Transport-level messages deal with connection lifecycle:
//   ping / pong / heartbeat / hello / server_info
//
// Session-level messages deal with ACP agent sessions:
//   start / input / cancel / switch_model / list_models / list_sessions
//   set_mode / set_config / load_session / resume_session / close_session
//   permission_response / authenticate / sync_request / show_qr / list_agents
//   etc.
//
// Incoming messages are unstructured JSON; the router below first checks for
// transport-level types, then routes everything else to the session dispatch.

import { discoverAgents } from "./discovery/agents.mjs";
import { loadRegistry, listRegistryAgents } from "./registry/registry.mjs";
import { getInstalledAgents, installAgent, uninstallAgent } from "./agents-store.mjs";
import { handleStart } from "./handlers/start.mjs";
import { handleInput } from "./handlers/input.mjs";
import { handleCancel } from "./handlers/cancel.mjs";
import { handleListModels } from "./handlers/list-models.mjs";
import { handleListSessions, clearSessionListCache, sessionTitleOverrides } from "./handlers/list-sessions.mjs";
import { handleSetMode } from "./handlers/set-mode.mjs";
import { handleSwitchModel } from "./handlers/switch-model.mjs";
import { handleLoadSession } from "./handlers/load-session.mjs";
import { handleResumeSession } from "./handlers/resume-session.mjs";
import { handleCloseSession } from "./handlers/close-session.mjs";
import { handleSetConfig } from "./handlers/set-config.mjs";
import { handlePermissionResponse } from "./handlers/permission.mjs";
import { handleAuth } from "./handlers/auth.mjs";
import { cleanupWsSessions, enqueueWsOp, getSession, getBufferedAfter, reclaimOrphanedSession, killSessionProcess, getAllSessions } from "./session.mjs";
import { SessionStatusWatcher, mergeSessionStatus } from "./discovery/session-watcher.mjs";
import { handleListWorkspaceFiles, handleFileDiff, handleFileLog, handleFileRead } from "./handlers/workspace-files.mjs";
import { sessionManager } from "./session-manager.mjs";

const PORT = parseInt(process.env.PORT || "", 10) || 12138;
const HOST_ID = getOrCreateHostId();

// ── createBridgeServer — 供 daemon/bootstrap.ts 调用 ──────────
// 创建一个独立的 HTTP+WSS 服务器，返回控制接口.
// 与模块级 legacy 路径共享 handleIncomingConnection 等处理函数.

export interface BridgeConfig {
  port: number;
  hostId?: string;
}

export interface BridgeApp {
  httpServer: http.Server;
  wss: WebSocketServer;
  port: number;
  stop: () => Promise<void>;
}

export function createBridgeServer(config: BridgeConfig): BridgeApp {
  const port = config.port;
  const hostId = config.hostId || HOST_ID;

  const httpServer = http.createServer((req: IncomingMessage, res: ServerResponse) => {
    handleHttpRequest(req, res);
  });
  const wss = new WebSocketServer({ server: httpServer });
  httpServer.listen(port, () => {
    console.log(`[server] listening on ws://0.0.0.0:${port} and IPv6 if available`);
  });

  // WebSocket keep-alive: ping all connected clients every 15s
  const pingInterval = setInterval(() => {
    wss.clients.forEach((sock: WebSocket) => {
      if ((sock as any).isDead) return;
      try { sock.ping(); } catch {}
    });
  }, 15000);
  wss.on('connection', (sock: WebSocket) => {
    (sock as any).isDead = false;
    sock.on('pong', () => { (sock as any).isDead = false; });
    sock.on('close', () => { (sock as any).isDead = true; });
  });

  // Wire up connections to message handlers
  wss.on("connection", (ws: WebSocket) => {
    handleIncomingConnection(ws);
  });

  startSessionWatcher(wss);

  return {
    httpServer,
    wss,
    port,
    stop: async () => {
      clearInterval(pingInterval);
      // Kill all agent subprocesses before closing
      for (const [, sess] of getAllSessions()) {
        try { killSessionProcess(sess); } catch {}
      }
      wss.clients.forEach(client => { try { client.close(); } catch {} });
      await new Promise<void>(resolve => wss.close(() => resolve()));
      await new Promise<void>(resolve => httpServer.close(() => resolve()));
    },
  };
}

// ── Backward compat: direct script execution ──────────────────
// When `node server.mjs` is run directly, the code below
// starts a server with QR support.
// When imported as a module (by bootstrap.ts), createBridgeServer
// above is used instead.
const isMainModule = process.argv[1] && (
  process.argv[1].replace(/\\/g, '/').endsWith('server.mjs')
);

// ── Pure functions (hoisted so createBridgeServer can call them) ──

/** Start the session watcher and broadcast changes to all connected clients. */
function startSessionWatcher(wss: WebSocketServer): void {
  // Debounced pending sessions: aggregate rapid watcher ticks into one broadcast
  const pendingSessions = new Map<string, { sessionId: string; status: string; lastActivity: number }>();
  let debounceTimer: ReturnType<typeof setTimeout> | undefined;

  function flushPending(): void {
    if (pendingSessions.size === 0) return;
    const sessions = Array.from(pendingSessions.values());
    pendingSessions.clear();
    debounceTimer = undefined;

    const payload = JSON.stringify({
      type: "session_status_update",
      sessions,
    });
    wss.clients.forEach((client: WebSocket) => {
      try { client.send(payload); } catch {}
    });
  }

  const watcher = new SessionStatusWatcher(5000);
  watcher.onStatusUpdate(({ added, removed, changed }) => {
    // Merge live SessionManager state: turnActive=true → "running"
    const activeIds = sessionManager.getActiveSessionIds();
    const finalAdded = activeIds.size > 0 ? mergeSessionStatus(added, activeIds) : added;
    const finalChanged = activeIds.size > 0 ? mergeSessionStatus(changed, activeIds) : changed;

    const all = [...finalAdded, ...finalChanged];
    if (all.length === 0) return;

    for (const s of all) {
      pendingSessions.set(s.sessionId, {
        sessionId: s.sessionId,
        status: s.status,
        lastActivity: s.lastActivity,
      });
    }

    // Debounce: reset timer on each watcher tick
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(flushPending, 500);
  });
  watcher.start();
  console.log("[server] session watcher started (5s interval, 500ms debounce)");
}

function collectHostIps(): string[] {
  const nets = os.networkInterfaces();
  const ips: string[] = [];
  for (const name of Object.keys(nets)) {
    // Skip virtual Ethernet (Hyper-V, Docker, WSL)
    if (name.startsWith('vEthernet') || name.startsWith('VirtualBox') ||
        name.startsWith('VMware') || name.startsWith('Bluetooth') ||
        name.includes('Loopback') || name.includes('lo')) {
      continue;
    }
    for (const net of nets[name]!) {
      if (!net.internal && net.family === 'IPv4') {
        ips.push(net.address);
      }
    }
  }
  ips.push(`HOST:${HOST_ID}`);
  return ips;
}

function sendJson(res: ServerResponse, statusCode: number, payload: object): void {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
    "Connection": "close",
  });
  res.end(body);
}

function handleHttpRequest(req: IncomingMessage, res: ServerResponse): void {
  if (req.method !== "GET") {
    sendJson(res, 400, { ok: false, error: "bad request" });
    return;
  }
  const url = new URL(req.url || "/", "http://localhost");
  if (url.pathname === "/probe") {
    sendJson(res, 200, {
      ok: true,
      kind: "bridge",
      hostId: HOST_ID,
      hostname: os.hostname(),
      ips: collectHostIps(),
      ts: Date.now(),
    });
    return;
  }
  res.writeHead(400, {
    "Content-Type": "text/plain",
    "Connection": "close",
  });
  res.end("WebSocket only");
}

function sendServerInfo(ws: WebSocket | any) {
  try {
    const hostname = os.hostname();
    const ips = collectHostIps();
    ws.send(JSON.stringify({
      type: "server_info",
      hostId: HOST_ID,
      ed25519PublicKeyHex: getOrCreateHostIdentity().ed25519PublicKeyHex,
      hostname,
      ips,
    }));
    console.log(`[server] sent server_info: ${hostname} (${ips.length} IPs)`);
  } catch (err) {
    console.log(`[server] failed to get host info: ${err}`);
  }
}

function handleIncomingConnection(transport: any) {
  console.log(`[server] Local client connected`);
  const originalSend = transport.send.bind(transport);
  transport.send = (data: string | Buffer) => originalSend(data);
  sendServerInfo(transport);
  // Heartbeat: respond to ping with pong via plain WS frame
  const HEARTBEAT_INTERVAL_MS = 10_000;
  setInterval(() => {
    try { transport.send(JSON.stringify({ type: "ping" })); } catch {}
  }, HEARTBEAT_INTERVAL_MS);

  function handlePlaintextMessage(rawStr: string) {
    let msg: any;
    try {
      msg = JSON.parse(rawStr);
    } catch {
      // Some relays may strip quotes from JSON keys/values. Try to fix.
      try {
        const fixed = rawStr
          .replace(/([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:/g, '$1"$2":')
          .replace(/:\s*([a-zA-Z_][a-zA-Z0-9_.-]*)\s*([,}])/g, ':"$1"$2');
        msg = JSON.parse(fixed);
      } catch {
        transport.send(JSON.stringify({ type: "error", text: "invalid json" }));
        return;
      }
    }

    const logPrefix = `[server] ← ${msg.type}`;
    const logDetails = msg.text ? ` text="${msg.text.slice(0, 60)}"` :
      msg.sessionId ? ` sessionId="${msg.sessionId?.slice(0, 20)}"` : '';
    console.log(`${logPrefix}${logDetails}`);

    // ── Transport layer: messages about the connection itself ──
    // These are handled first and don't enter the session routing.
    if (handleTransportMessage(msg, rawStr)) {
      return;
    }

    // ── Session layer ──────────────────────────────────────────
    // Try to reclaim orphaned session for any message with a sessionId.
    if (msg.sessionId) {
      const reclaimed = reclaimOrphanedSession(msg.sessionId, transport);
      if (reclaimed) {
        console.log(`[server] reclaimed orphaned session ${msg.sessionId?.slice(0, 20)}`);
      }
    }

    // Dispatch to the appropriate handler.
    handleSessionMessage(msg, rawStr);
  }

  /**
   * Handle transport-level messages (heartbeat, ping/pong, etc.)
   * Returns true if the message was consumed, false otherwise.
   */
  function handleTransportMessage(msg: any, rawStr: string): boolean {
    switch (msg.type) {
      case "heartbeat":
        transport.send(JSON.stringify({ type: "heartbeat", ts: msg.ts || Date.now() }));
        return true;

      case "ping":
        // Transport-level liveness check — respond immediately.
        originalSend(JSON.stringify({ type: "pong" }));
        return true;

      default:
        return false;
    }
  }

  function handleSessionMessage(msg: any, _rawStr: string): void {
    // Support two inbound formats:
    //   Legacy: { type: "start", ... }
    //   Layered: { type: "session", message: { type: "start", ... } }
    const sessionMsg = msg.type === "session" && msg.message ? msg.message : msg;

    switch (sessionMsg.type) {
      case "start":
        console.log(`[server] handleStart agent="${sessionMsg.agent || "opencode"}" cwd="${sessionMsg.cwd || process.cwd()}"`);
        // Send immediate ack before spawning agent to prevent WS timeout
        transport.send(JSON.stringify({ type: "start_ack" }));
        clearSessionListCache(transport);
        handleStart(transport, sessionMsg).catch((err: Error) => {
          console.log(`[server] handleStart error: ${err.message}`);
        });
        break;

      case "list_agents": {
        let agents: any[];
        try {
          agents = discoverAgents();
        } catch (e) {
          console.log(`[server] discoverAgents error: ${e}`);
          agents = [];
        }
        console.log(`[server] → agent_list (${agents.length} agents)`);
        transport.send(JSON.stringify({ type: "agent_list", agents }));
        break;
      }

      case "list_registry_agents": {
        try {
          loadRegistry();
          const regAgents = listRegistryAgents();
          console.log(`[server] → registry_agents_list (${regAgents.length} agents)`);
          transport.send(JSON.stringify({ type: "registry_agents_list", agents: regAgents }));
        } catch (e: any) {
          console.log(`[server] list_registry_agents error: ${e}`);
          transport.send(JSON.stringify({ type: "registry_agents_list", agents: [] }));
        }
        break;
      }

      case "install_agent": {
        const agentId = String(sessionMsg.agentId || "");
        console.log(`[server] install_agent: ${agentId}`);
        try {
          if (!agentId) throw new Error("missing agentId");
          installAgent(agentId, "registry");
          transport.send(JSON.stringify({ type: "install_agent_done", agentId, ok: true }));
        } catch (e: any) {
          console.log(`[server] install_agent error: ${e.message}`);
          transport.send(JSON.stringify({ type: "install_agent_done", agentId, ok: false, error: e.message }));
        }
        break;
      }

      case "uninstall_agent": {
        const agentId = String(sessionMsg.agentId || "");
        console.log(`[server] uninstall_agent: ${agentId}`);
        try {
          if (!agentId) throw new Error("missing agentId");
          const removed = uninstallAgent(agentId);
          transport.send(JSON.stringify({ type: "uninstall_agent_done", agentId, ok: removed }));
        } catch (e: any) {
          console.log(`[server] uninstall_agent error: ${e.message}`);
          transport.send(JSON.stringify({ type: "uninstall_agent_done", agentId, ok: false, error: e.message }));
        }
        break;
      }

      case "install_custom_agent": {
        const command = String(sessionMsg.command || "");
        const args = Array.isArray(sessionMsg.args) ? sessionMsg.args as string[] : [];
        const name = String(sessionMsg.name || command.split(/[\\/]/).pop() || "custom-agent");
        console.log(`[server] install_custom_agent: ${name} cmd=${command}`);
        try {
          if (!command) throw new Error("missing command");
          installAgent(name, "custom", { command, args });
          transport.send(JSON.stringify({ type: "install_agent_done", agentId: name, ok: true }));
        } catch (e: any) {
          console.log(`[server] install_custom_agent error: ${e.message}`);
          transport.send(JSON.stringify({ type: "install_agent_done", agentId: name, ok: false, error: e.message }));
        }
        break;
      }

      case "input":
        console.log(`[server] handleInput session="${sessionMsg.sessionId?.slice(0, 20)}" text="${sessionMsg.text?.slice(0, 80)}"`);
        handleInput(transport, sessionMsg.sessionId, sessionMsg.text);
        break;

      case "cancel":
        console.log(`[server] handleCancel session="${sessionMsg.sessionId?.slice(0, 20)}"`);
        handleCancel(transport, sessionMsg.sessionId);
        break;

      case "switch_model":
        console.log(`[server] handleSwitchModel session="${sessionMsg.sessionId?.slice(0, 20)}" model="${sessionMsg.model}"`);
        handleSwitchModel(transport, sessionMsg.sessionId, sessionMsg.model).catch((err: Error) => {
          console.log(`[server] handleSwitchModel error: ${err.message}`);
        });
        break;

      case "list_models":
        console.log(`[server] handleListModels agent="${sessionMsg.agent || ""}"`);
        enqueueWsOp(transport, () => handleListModels(transport, sessionMsg.agent, Boolean(sessionMsg.refresh)));
        break;

      case "list_sessions":
        console.log(`[server] handleListSessions cwd="${sessionMsg.cwd || ""}" agent="${sessionMsg.agent || ""}"`);
        enqueueWsOp(transport, () => handleListSessions(transport, sessionMsg.cwd, sessionMsg.agent));
        break;

      case "set_mode":
        console.log(`[server] handleSetMode session="${sessionMsg.sessionId?.slice(0, 20)}" mode="${sessionMsg.modeId}"`);
        handleSetMode(transport, sessionMsg.sessionId, sessionMsg.modeId).catch((err: Error) => {
          console.log(`[server] handleSetMode error: ${err.message}`);
        });
        break;

      case "set_config":
        console.log(`[server] handleSetConfig session="${sessionMsg.sessionId?.slice(0, 20)}" config="${sessionMsg.configId}" value="${sessionMsg.value}"`);
        handleSetConfig(transport, sessionMsg.sessionId, sessionMsg.configId, sessionMsg.value).catch((err: Error) => {
          console.log(`[server] handleSetConfig error: ${err.message}`);
        });
        break;

      case "load_session":
        console.log(`[server] handleLoadSession target="${sessionMsg.sessionId?.slice(0, 20)}" agent="${sessionMsg.agent || "opencode"}"`);
        clearSessionListCache(transport);
        enqueueWsOp(transport, () => handleLoadSession(transport, sessionMsg));
        break;

      case "resume_session":
        console.log(`[server] handleResumeSession target="${sessionMsg.sessionId?.slice(0, 20)}" agent="${sessionMsg.agent || "opencode"}"`);
        clearSessionListCache(transport);
        enqueueWsOp(transport, () => handleResumeSession(transport, sessionMsg));
        break;

      case "close_session":
        console.log(`[server] handleCloseSession session="${sessionMsg.sessionId?.slice(0, 20)}"`);
        enqueueWsOp(transport, () => handleCloseSession(transport, sessionMsg.sessionId));
        break;

      case "permission_response":
        console.log(`[server] handlePermissionResponse session="${sessionMsg.sessionId?.slice(0, 20)}" outcome="${sessionMsg.outcome}"`);
        handlePermissionResponse(
          transport,
          sessionMsg.sessionId,
          sessionMsg.requestId,
          sessionMsg.outcome,
          sessionMsg.optionId,
        );
        break;

      case "authenticate":
        console.log(`[server] handleAuth session="${sessionMsg.sessionId?.slice(0, 20)}" method="${sessionMsg.methodId}"`);
        handleAuth(transport, sessionMsg.sessionId, sessionMsg.methodId).catch((err: Error) => {
          console.log(`[server] handleAuth error: ${err.message}`);
        });
        break;

      case "list_workspace_files":
        console.log(`[server] list_workspace_files cwd="${sessionMsg.cwd || ""}"`);
        enqueueWsOp(transport, () => handleListWorkspaceFiles(transport, { cwd: sessionMsg.cwd || process.cwd() }));
        break;

      case "get_file_diff":
        enqueueWsOp(transport, () => handleFileDiff(transport, { cwd: sessionMsg.cwd || process.cwd(), path: sessionMsg.text || sessionMsg.path || "" }));
        break;

      case "get_file_log":
        enqueueWsOp(transport, () => handleFileLog(transport, { cwd: sessionMsg.cwd || process.cwd(), path: sessionMsg.text || sessionMsg.path || "" }));
        break;

      case "get_file_content":
        enqueueWsOp(transport, () => handleFileRead(transport, { cwd: sessionMsg.cwd || process.cwd(), path: sessionMsg.text || sessionMsg.path || "" }));
        break;

      case "sync_request": {
        const syncSessionId = sessionMsg.sessionId as string;
        const lastMessageId = sessionMsg.lastMessageId as string || '';
        console.log(`[server] sync_request session="${syncSessionId?.slice(0, 20)}" lastMessageId="${lastMessageId?.slice(0, 20)}"`);
        const sess = getSession(syncSessionId);
        if (sess) {
          const syncResult = getBufferedAfter(syncSessionId, lastMessageId);
          const safeEntries = syncResult.entries
            .map(e => {
              try {
                const parsed = JSON.parse(e.payload);
                // payload is stored as {type:"agent_event", sessionId, event: {...}}
                // client expects just the inner event object; fallback to parsed for non-event payloads
                const payload = parsed.event || parsed;
                if (payload && typeof payload === "object") {
                  payload.messageId = e.messageId;
                }
                return { messageId: e.messageId, payload, timestamp: e.timestamp };
              } catch {
                return null;
              }
            })
            .filter(Boolean);
          transport.send(JSON.stringify({
            type: "sync_response",
            sessionId: syncSessionId,
            entries: safeEntries,
            overflow: syncResult.overflow,
          }));
          console.log(`[server] sync_response ${safeEntries.length} entries for ${syncSessionId?.slice(0, 20)} overflow=${syncResult.overflow}`);
        } else {
          transport.send(JSON.stringify({
            type: "sync_response",
            sessionId: syncSessionId,
            entries: [],
            error: "session not found",
          }));
        }
        break;
      }

      default:
        console.log(`[server] unknown message type: ${sessionMsg.type}`);
    }
  }

  // ── Incoming message handling ──
  function onRawBuffer(raw: Buffer | string): void {
    const buf = typeof raw === 'string' ? Buffer.from(raw) : raw;
    const rawStr = buf.toString('utf-8');
    handlePlaintextMessage(rawStr);
  }

  function onClose(): void {
    console.log(`[server] Local client disconnected, cleaning up sessions`);
    clearSessionListCache(transport);
    cleanupWsSessions(transport);
  }

  // Wire up message delivery
  transport.on("message", (raw: Buffer) => onRawBuffer(raw));
  transport.on("close", () => onClose());
}

if (isMainModule) {
  // Legacy standalone path: create HTTP + WSS server
  const httpServer = http.createServer((req: IncomingMessage, res: ServerResponse) => {
    handleHttpRequest(req, res);
  });
  const wss = new WebSocketServer({ server: httpServer });
  httpServer.listen(PORT, () => {
    console.log(`[server] listening on ws://0.0.0.0:${PORT} and IPv6 if available`);
  });

  // WebSocket keep-alive: ping all connected clients every 15s
  const pingInterval = setInterval(() => {
    wss.clients.forEach((sock: WebSocket) => {
      if ((sock as any).isDead) return;
      try { sock.ping(); } catch {}
    });
  }, 15000);
  wss.on('connection', (sock: WebSocket) => {
    (sock as any).isDead = false;
    sock.on('pong', () => { (sock as any).isDead = false; });
    sock.on('close', () => { (sock as any).isDead = true; });
  });

  wss.on("connection", (ws: WebSocket) => {
    handleIncomingConnection(ws);
  });

  console.log('[server] started (legacy mode: node server.mjs)');
  startSessionWatcher(wss);
} // end if (isMainModule)
