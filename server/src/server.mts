import { WebSocketServer, type WebSocket } from "ws";
import http, { type IncomingMessage, type ServerResponse } from "node:http";
import os from "os";
import { getOrCreateHostId } from "./host-identity.mjs";
import { isAuthorizedHeader } from "./auth-token.mjs";
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
import { findExecutable, getInstalledAgents, installAgent, uninstallAgent } from "./agents-store.mjs";
import { handleStart } from "./handlers/start.mjs";
import { handleInput } from "./handlers/input.mjs";
import { handleCancel } from "./handlers/cancel.mjs";
import { handleListModels } from "./handlers/list-models.mjs";
import { handleListSessions } from "./handlers/list-sessions.mjs";
import { handleCloseSession, markExternalSessionClosing } from "./handlers/close-session.mjs";
import { handleSetMode } from "./handlers/set-mode.mjs";
import { handleSwitchModel } from "./handlers/switch-model.mjs";
import { handleLoadHistoryPage, handleLoadSession } from "./handlers/load-session.mjs";
import { handleResumeSession } from "./handlers/resume-session.mjs";
import { handleSetConfig } from "./handlers/set-config.mjs";
import { handlePermissionResponse } from "./handlers/permission.mjs";
import { handleAuth } from "./handlers/auth.mjs";

import { SessionStatusWatcher, mergeSessionStatus } from "./discovery/session-watcher.mjs";
import { handleListWorkspaceFiles, handleFileDiff, handleFileLog, handleFileRead } from "./handlers/workspace-files.mjs";
import { SessionOperationError, SessionOwnerError, sessionManager } from "./session-manager.mjs";
import { setTitle as setSessionTitle } from "./session-titles.mjs";
import { parseClientMessage, type JsonRecord } from "./protocol-validation.mjs";
import { handleListHerdrWorkspaces, handleCreateHerdrWorkspace, handleCreateHerdrAgent, handleFocusHerdrTarget, handleInteractHerdrBlocked, handleListHerdrIntegrations, handleInstallHerdrIntegration } from "./handlers/herdr-actions.mjs";
import { watchAmbientSessions, listAmbientSessions } from "./discovery/ambient-session.mjs";
import { detectHostCapabilities, invalidateHostCapabilities } from "./discovery/host-capabilities.mjs";
import { installNativeHook, uninstallNativeHook } from "./discovery/native-hooks.mjs";
import { installAcpAdapter, uninstallAcpAdapter } from "./discovery/acp-adapters.mjs";

const PORT = parseInt(process.env.PORT || "", 10) || 12138;
const HOST_ID = getOrCreateHostId();

// Exported for tests: interface classification is pure given os.networkInterfaces().
export { collectHostIps as collectHostIpsForTest };

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

function sendUnauthorizedUpgrade(socket: { write: (data: string) => void; destroy: () => void }): void {
  const body = JSON.stringify({ ok: false, error: "unauthorized", code: "AUTH_REQUIRED" });
  try {
    socket.write(
      `HTTP/1.1 401 Unauthorized\r\nContent-Type: application/json\r\nContent-Length: ${Buffer.byteLength(body)}\r\nConnection: close\r\n\r\n${body}`,
    );
  } finally {
    socket.destroy();
  }
}

function createAuthenticatedWebSocketServer(httpServer: http.Server): WebSocketServer {
  const wss = new WebSocketServer({ noServer: true, maxPayload: 10 * 1024 * 1024 });
  httpServer.on("upgrade", (req, socket, head) => {
    const url = new URL(req.url || "/", "http://localhost");
    const queryToken = url.searchParams.get("token");
    if (!isAuthorizedHeader(req.headers.authorization) && (!queryToken || !isAuthorizedHeader(`Bearer ${queryToken}`))) {
      sendUnauthorizedUpgrade(socket);
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit("connection", ws, req);
    });
  });
  return wss;
}

export function createBridgeServer(config: BridgeConfig): BridgeApp {
  const port = config.port;
  const hostId = config.hostId || HOST_ID;

  const httpServer = http.createServer((req: IncomingMessage, res: ServerResponse) => {
    handleHttpRequest(req, res, hostId);
  });
  const wss = createAuthenticatedWebSocketServer(httpServer);
  httpServer.listen(port, () => {
    console.log(`[server] listening on ws://0.0.0.0:${port} and IPv6 if available`);
  });

  // WebSocket keep-alive: ping all connected clients every 15s
  const pingInterval = setInterval(() => {
    wss.clients.forEach((sock: WebSocket) => {
      // 上一轮 ping 未收到 pong（isDead 仍为 true）→ 判定死连接并 terminate
      if ((sock as any).isDead) {
        try { sock.terminate(); } catch {}
        return;
      }
      (sock as any).isDead = true;
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
    handleIncomingConnection(ws, hostId);
  });

  const stopSessionWatcher = startSessionWatcher(wss);

  return {
    httpServer,
    wss,
    port,
    stop: async () => {
      clearInterval(pingInterval);
      stopSessionWatcher();
      // Kill all agent subprocesses before closing
      for (const [, sess] of sessionManager.getAllSessions()) {
        try { sessionManager.killSessionProcess(sess); } catch {}
      }
      sessionManager.stop();
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
function startSessionWatcher(wss: WebSocketServer): () => void {
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
    // Get canonical SessionManager state — filter filesystem results to only
    // include identifiers matching known live sessions. Static filesystem labels
    // (e.g. "opencode-active") without a matching SessionManager session are dropped.
    const knownIds = new Set(sessionManager.getAllSessions().keys());
    const activeIds = sessionManager.getActiveSessionIds();

    const allChanges = [...added, ...changed];
    const merged = mergeSessionStatus(allChanges, activeIds, knownIds);

    // Build complete snapshot: merged disk state + all SessionManager sessions.
    const result = new Map<string, { sessionId: string; status: string; lastActivity: number }>();
    for (const s of merged) {
      result.set(s.sessionId, {
        sessionId: s.sessionId,
        status: s.status,
        lastActivity: s.lastActivity,
      });
    }

    const now = Date.now();
    for (const [id, sess] of sessionManager.getAllSessions()) {
      if (!result.has(id)) {
        result.set(id, {
          sessionId: id,
          status: sess.turnActive ? "running" : "idle",
          lastActivity: sess.lastActivity || now,
        });
      }
    }

    if (result.size === 0) return;

    for (const [id, entry] of result) {
      pendingSessions.set(id, entry);
    }

    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(flushPending, 500);
  });

  const stopAmbientWatcher = watchAmbientSessions(() => {
    const ambientSessions = listAmbientSessions();
    if (ambientSessions.length === 0) return;
    for (const amb of ambientSessions) {
      pendingSessions.set(amb.sessionId, {
        sessionId: amb.sessionId,
        status: amb.status,
        lastActivity: amb.updatedAt,
      });
    }
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(flushPending, 500);
  });

  watcher.start();
  console.log("[server] session watcher started (5s interval, 500ms debounce)");
  return () => {
    clearTimeout(debounceTimer);
    pendingSessions.clear();
    try { stopAmbientWatcher(); } catch {}
    watcher.stop();
  };
}

function collectHostIps(hostId: string): string[] {
  const nets = os.networkInterfaces();
  const lanV4: string[] = [];
  const globalV6: string[] = [];
  const ulaV6: string[] = [];
  const otherV4: string[] = [];

  for (const name of Object.keys(nets)) {
    for (const net of nets[name] ?? []) {
      if (net.internal) continue;
      const addr = net.address;
      if (net.family === 'IPv4') {
        if (/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(addr)) {
          lanV4.push(addr);
        } else if (!addr.startsWith('169.254.')) {
          otherV4.push(addr);
        }
      } else if (net.family === 'IPv6') {
        const bare = addr.split('%')[0];
        if (bare.startsWith('fe80') || bare === '::1') continue;
        if (/^f[cd]/i.test(bare)) {
          ulaV6.push(bare);
        } else {
          globalV6.push(bare);
        }
      }
    }
  }

  const ips = [...lanV4, ...globalV6, ...ulaV6, ...otherV4];
  ips.push(`HOST:${hostId}`);
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

function handleHttpRequest(req: IncomingMessage, res: ServerResponse, hostId: string = HOST_ID): void {
  if (req.method !== "GET") {
    sendJson(res, 400, { ok: false, error: "bad request" });
    return;
  }
  const url = new URL(req.url || "/", "http://localhost");
  if (url.pathname === "/probe") {
    const queryToken = url.searchParams.get("token");
    if (!isAuthorizedHeader(req.headers.authorization) && (!queryToken || !isAuthorizedHeader(`Bearer ${queryToken}`))) {
      sendJson(res, 401, { ok: false, error: "unauthorized", code: "AUTH_REQUIRED" });
      return;
    }
    sendJson(res, 200, {
      ok: true,
      kind: "bridge",
      hostId,
      hostname: os.hostname(),
      ips: collectHostIps(hostId),
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

function sendServerInfo(ws: WebSocket | any, hostId: string): void {
  try {
    const hostname = os.hostname();
    const ips = collectHostIps(hostId);
    ws.send(JSON.stringify({
      type: "server_info",
      hostId,
      hostname,
      ips,
    }));
    console.log(`[server] sent server_info: ${hostname} (${ips.length} IPs)`);
  } catch (err) {
    console.log(`[server] failed to get host info: ${err}`);
  }
}

export function handleIncomingConnection(transport: any, hostId: string = HOST_ID) {
  console.log(`[server] Local client connected`);
  const originalSend = transport.send.bind(transport);
  transport.send = (data: string | Buffer) => originalSend(data);
  sendServerInfo(transport, hostId);
  // Heartbeat: respond to ping with pong via plain WS frame
  const HEARTBEAT_INTERVAL_MS = 10_000;
  const heartbeatTimer = setInterval(() => {
    try { transport.send(JSON.stringify({ type: "ping" })); } catch {}
  }, HEARTBEAT_INTERVAL_MS);

  function sendProtocolError(code: string, text: string): void {
    try {
      transport.send(JSON.stringify({ type: "error", code, text }));
    } catch { /* WS already closed */ }
  }

  function handlePlaintextMessage(rawStr: string): void {
    let parsed: ReturnType<typeof parseClientMessage>;
    try {
      parsed = parseClientMessage(rawStr);
    } catch {
      sendProtocolError("INVALID_MESSAGE", "Message does not match the WS protocol");
      return;
    }
    if (!parsed.ok) {
      sendProtocolError(parsed.code, parsed.text);
      return;
    }

    const msg = parsed.message;
    try {
      const logPrefix = `[server] ← ${msg.type}`;
      const logDetails = typeof msg.text === "string" ? ` text="${msg.text.slice(0, 60)}"` :
        typeof msg.sessionId === "string" ? ` sessionId="${msg.sessionId.slice(0, 20)}"` : '';
      console.log(`${logPrefix}${logDetails}`);

      // ── Transport layer: messages about the connection itself ──
      if (handleTransportMessage(msg, rawStr)) return;

      // ── Session layer ──────────────────────────────────────────
      handleSessionMessage(msg, rawStr);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.log(`[server] message handler error: ${message}`);
      sendProtocolError("MESSAGE_HANDLER_FAILED", "Message handler failed");
    }
  }

  /**
   * Handle transport-level messages (heartbeat, ping/pong, etc.)
   * Returns true if the message was consumed, false otherwise.
   */
  function handleTransportMessage(msg: JsonRecord, _rawStr: string): boolean {
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

  function handleSessionMessage(msg: JsonRecord, _rawStr: string): void {
    // Support two inbound formats:
    //   Legacy: { type: "start", ... }
    //   Layered: { type: "session", message: { type: "start", ... } }
    const sessionMsg: any = msg.type === "session" ? msg.message : msg;

    switch (sessionMsg.type) {
      case "start":
        console.log(`[server] handleStart agent="${sessionMsg.agent || "omp"}" cwd="${sessionMsg.cwd || ""}"`);
        // handleStart 到达 getOrCreate 的首个 await 前会同步设置 pendingCreates；WS 消息有序，下一条 Start 必然看到准入锁。
        if (sessionManager.hasPendingCreate(transport)) {
          // 拒绝重复 Start：已有创建任务进行中，不占准入锁也不发 start_ack
          transport.send(JSON.stringify({ type: "start_failed", code: "START_ALREADY_IN_PROGRESS", text: "A session is already being created." }));
          break;
        }
        // 仅在成功占用准入锁后发送 ack，避免拒绝请求先收到 start_ack。
        transport.send(JSON.stringify({ type: "start_ack" }));
        handleStart(transport, sessionMsg).catch((err: Error) => {
          console.log(`[server] handleStart error: ${err.message}`);
        });
        break;

      case "list_herdr_workspaces":
        sessionManager.enqueueWsOp(transport, () => handleListHerdrWorkspaces(transport));
        break;

      case "create_herdr_workspace":
        sessionManager.enqueueWsOp(transport, () => handleCreateHerdrWorkspace(transport, sessionMsg as any));
        break;

      case "create_herdr_agent":
        sessionManager.enqueueWsOp(transport, () => handleCreateHerdrAgent(transport, sessionMsg as any));
        break;

      case "focus_herdr_target":
        sessionManager.enqueueWsOp(transport, () => handleFocusHerdrTarget(transport, sessionMsg as any));
        break;

      case "interact_herdr_blocked":
        sessionManager.enqueueWsOp(transport, () => handleInteractHerdrBlocked(transport, sessionMsg as any));
        break;

      case "list_herdr_integrations":
        sessionManager.enqueueWsOp(transport, () => handleListHerdrIntegrations(transport));
        break;

      case "install_herdr_integration":
        sessionManager.enqueueWsOp(transport, () => handleInstallHerdrIntegration(transport, sessionMsg as any));
        break;

      case "install_native_hook": {
        const agentId = String(sessionMsg.agentId || "");
        console.log(`[server] install_native_hook: ${agentId}`);
        sessionManager.enqueueWsOp(transport, async () => {
          try {
            const res = await installNativeHook(agentId);
            if (!res.ok) throw new Error(res.error || "Installation failed");
            invalidateHostCapabilities();
            transport.send(JSON.stringify({ type: "install_native_hook_done", agentId, ok: true }));
          } catch (err: any) {
            console.log(`[server] install_native_hook error: ${err.message}`);
            transport.send(JSON.stringify({ type: "install_native_hook_done", agentId, ok: false, error: err.message }));
          }
        });
        break;
      }

      case "uninstall_native_hook": {
        const agentId = String(sessionMsg.agentId || "");
        console.log(`[server] uninstall_native_hook: ${agentId}`);
        sessionManager.enqueueWsOp(transport, async () => {
          try {
            const res = await uninstallNativeHook(agentId);
            if (!res.ok) throw new Error(res.error || "Uninstallation failed");
            invalidateHostCapabilities();
            transport.send(JSON.stringify({ type: "uninstall_native_hook_done", agentId, ok: true }));
          } catch (err: any) {
            console.log(`[server] uninstall_native_hook error: ${err.message}`);
            transport.send(JSON.stringify({ type: "uninstall_native_hook_done", agentId, ok: false, error: err.message }));
          }
        });
        break;
      }

      case "install_acp_adapter": {
        const agentId = String(sessionMsg.agentId || "");
        console.log(`[server] install_acp_adapter: ${agentId}`);
        sessionManager.enqueueWsOp(transport, async () => {
          try {
            const res = await installAcpAdapter(agentId);
            if (!res.ok) throw new Error(res.error || "Adapter installation failed");
            invalidateHostCapabilities();
            transport.send(JSON.stringify({ type: "install_acp_adapter_done", agentId, ok: true, path: res.path }));
          } catch (err: any) {
            console.log(`[server] install_acp_adapter error: ${err.message}`);
            transport.send(JSON.stringify({ type: "install_acp_adapter_done", agentId, ok: false, error: err.message }));
          }
        });
        break;
      }

      case "uninstall_acp_adapter": {
        const agentId = String(sessionMsg.agentId || "");
        console.log(`[server] uninstall_acp_adapter: ${agentId}`);
        sessionManager.enqueueWsOp(transport, async () => {
          try {
            const res = await uninstallAcpAdapter(agentId);
            if (!res.ok) throw new Error(res.error || "Adapter uninstallation failed");
            invalidateHostCapabilities();
            transport.send(JSON.stringify({ type: "uninstall_acp_adapter_done", agentId, ok: true }));
          } catch (err: any) {
            console.log(`[server] uninstall_acp_adapter error: ${err.message}`);
            transport.send(JSON.stringify({ type: "uninstall_acp_adapter_done", agentId, ok: false, error: err.message }));
          }
        });
        break;
      }

      case "get_host_capabilities": {
        detectHostCapabilities(false)
          .then((capabilities) => {
            transport.send(JSON.stringify({ type: "host_capabilities", hostId, capabilities }));
          })
          .catch((err) => {
            console.log(`[server] get_host_capabilities error: ${err}`);
          });
        break;
      }

      case "refresh_host_capabilities": {
        detectHostCapabilities(true)
          .then((capabilities) => {
            transport.send(JSON.stringify({ type: "host_capabilities", hostId, capabilities }));
          })
          .catch((err) => {
            console.log(`[server] refresh_host_capabilities error: ${err}`);
          });
        break;
      }

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
          // Registry entries are static metadata only; runtime availability
          // comes from host_capabilities.
          const regAgents = listRegistryAgents();
          console.log(`[server] → registry_agents_list (${regAgents.length} agents)`);
          transport.send(JSON.stringify({ type: "registry_agents_list", registryAgents: regAgents }));
        } catch (e: any) {
          console.log(`[server] list_registry_agents error: ${e}`);
          transport.send(JSON.stringify({ type: "registry_agents_list", registryAgents: [] }));
        }
        break;
      }

      case "install_agent": {
        const agentId = String(sessionMsg.agentId || "");
        console.log(`[server] install_agent: ${agentId}`);
        try {
          if (!agentId) throw new Error("missing agentId");
          installAgent(agentId, "registry");
          invalidateHostCapabilities();
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
          invalidateHostCapabilities();
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
          invalidateHostCapabilities();
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
        sessionManager.enqueueWsOp(transport, () => handleListModels(transport, sessionMsg.agent, Boolean(sessionMsg.refresh)));
        break;

      case "list_sessions":
        console.log(`[server] handleListSessions cwd="${sessionMsg.cwd || ""}" agent="${sessionMsg.agent || ""}" useHerdr="${sessionMsg.useHerdr ?? ""}"`);
        sessionManager.enqueueWsOp(transport, () => handleListSessions(
          transport,
          sessionMsg.cwd,
          sessionMsg.agent,
          sessionMsg.useHerdr as boolean | undefined,
          sessionMsg.requestId as string | undefined,
        ));
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
        console.log(`[server] handleLoadSession target="${sessionMsg.sessionId?.slice(0, 20)}" agent="${sessionMsg.agent || "omp"}"`);
        sessionManager.enqueueWsOp(transport, () => handleLoadSession(transport, sessionMsg));
        break;

      case "load_history_page":
        sessionManager.enqueueWsOp(transport, () => handleLoadHistoryPage(transport, sessionMsg));
        break;

      case "resume_session":
        console.log(`[server] handleResumeSession target="${sessionMsg.sessionId?.slice(0, 20)}" agent="${sessionMsg.agent || "omp"}"`);
        sessionManager.enqueueWsOp(transport, () => handleResumeSession(transport, sessionMsg));
        break;

      case "close_session":
        console.log(`[server] handleCloseSession session="${sessionMsg.sessionId?.slice(0, 20)}"`);
        if (sessionMsg.sessionId?.startsWith("herdr:") || sessionMsg.sessionId?.startsWith("ambient:")) {
          markExternalSessionClosing(sessionMsg.sessionId);
          sessionManager.enqueueWsOp(transport, () => handleCloseSession(transport, sessionMsg.sessionId));
          break;
        }
        try {
          // Reserve the close before queueing the ACP await so a following
          // input cannot claim the same session while closeSession is pending.
          sessionManager.beginClose(sessionMsg.sessionId, transport);
        } catch (err: unknown) {
          const code = err instanceof SessionOwnerError || err instanceof SessionOperationError
            ? err.code
            : "SESSION_ACCESS_DENIED";
          const message = err instanceof Error ? err.message : String(err);
          transport.send(JSON.stringify({ type: "error", sessionId: sessionMsg.sessionId, code, text: message }));
          break;
        }
        sessionManager.enqueueWsOp(transport, () => handleCloseSession(transport, sessionMsg.sessionId));
        break;

      case "rename_session": {
        const sid = sessionMsg.sessionId as string;
        const text = sessionMsg.text as string;
        console.log(`[server] rename_session session="${sid?.slice(0, 20)}" title="${text?.slice(0, 60)}"`);
        if (sid && text && text.trim().length > 0) {
          try {
            sessionManager.assertOwner(sid, transport);
            setSessionTitle(sid, text.trim());
            transport.send(JSON.stringify({ type: "session_renamed", sessionId: sid, title: text.trim() }));
          } catch (err: unknown) {
            const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
            const message = err instanceof Error ? err.message : String(err);
            transport.send(JSON.stringify({ type: "error", sessionId: sid, code, text: message }));
          }
        }
        break;
      }

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
        sessionManager.enqueueWsOp(transport, () => handleListWorkspaceFiles(transport, { cwd: sessionMsg.cwd || "", requestId: sessionMsg.requestId }));
        break;

      case "get_file_diff":
        sessionManager.enqueueWsOp(transport, () => handleFileDiff(transport, { cwd: sessionMsg.cwd || "", path: sessionMsg.text || sessionMsg.path || "", requestId: sessionMsg.requestId }));
        break;

      case "get_file_log":
        sessionManager.enqueueWsOp(transport, () => handleFileLog(transport, { cwd: sessionMsg.cwd || "", path: sessionMsg.text || sessionMsg.path || "", requestId: sessionMsg.requestId }));
        break;

      case "get_file_content":
        sessionManager.enqueueWsOp(transport, () => handleFileRead(transport, { cwd: sessionMsg.cwd || "", path: sessionMsg.text || sessionMsg.path || "", requestId: sessionMsg.requestId }));
        break;

      case "sync_request": {
        const syncSessionId = sessionMsg.sessionId as string;
        const lastMessageId = sessionMsg.lastMessageId as string || '';
        console.log(`[server] sync_request session="${syncSessionId?.slice(0, 20)}" lastMessageId="${lastMessageId?.slice(0, 20)}"`);
        if (syncSessionId.startsWith("herdr:") || syncSessionId.startsWith("ambient:")) {
          sessionManager.enqueueWsOp(transport, () => handleLoadSession(transport, { sessionId: syncSessionId }));
          break;
        }
        const sess = sessionManager.reclaimOrphanedSession(syncSessionId, transport);
        if (sess) {
          const syncResult = sessionManager.replayBuffer(syncSessionId, lastMessageId, transport);
          const safeEntries = syncResult.entries
            .map(e => {
              try {
                const parsed = JSON.parse(e.payload);
                if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null;
                // Replay the complete protocol envelope. The Flutter client
                // must be able to route session_context_replaced and other
                // session-scoped messages, not only inner ACP events.
                const payload = {
                  ...parsed,
                  sessionId: parsed.sessionId || syncSessionId,
                  messageId: e.messageId,
                };
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
            turnActive: sess.turnActive,
          }));
          console.log(`[server] sync_response ${safeEntries.length} entries for ${syncSessionId?.slice(0, 20)} overflow=${syncResult.overflow}`);
        } else {
          try {
            sessionManager.assertOwner(syncSessionId, transport);
          } catch (err: unknown) {
            const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
            const message = err instanceof Error ? err.message : String(err);
            transport.send(JSON.stringify({ type: "error", sessionId: syncSessionId, code, text: message }));
          }
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
    clearInterval(heartbeatTimer);
    console.log(`[server] Local client disconnected, cleaning up sessions`);
    sessionManager.cleanupWsSessions(transport);
  }

  // Wire up message delivery
  transport.on("message", (raw: Buffer) => onRawBuffer(raw));
  transport.on("close", () => onClose());
}

if (isMainModule) {
  // Legacy standalone path: create HTTP + WSS server
  const httpServer = http.createServer((req: IncomingMessage, res: ServerResponse) => {
    handleHttpRequest(req, res, HOST_ID);
  });
  const wss = createAuthenticatedWebSocketServer(httpServer);
  httpServer.listen(PORT, () => {
    console.log(`[server] listening on ws://0.0.0.0:${PORT} and IPv6 if available`);
  });
  // WebSocket keep-alive: ping all connected clients every 15s
  const pingInterval = setInterval(() => {
    wss.clients.forEach((sock: WebSocket) => {
      // 上一轮 ping 未收到 pong（isDead 仍为 true）→ 判定死连接并 terminate
      if ((sock as any).isDead) {
        try { sock.terminate(); } catch {}
        return;
      }
      (sock as any).isDead = true;
      try { sock.ping(); } catch {}
    });
  }, 15000);
  wss.on('connection', (sock: WebSocket) => {
    (sock as any).isDead = false;
    sock.on('pong', () => { (sock as any).isDead = false; });
    sock.on('close', () => { (sock as any).isDead = true; });
  });

  wss.on("connection", (ws: WebSocket) => {
    handleIncomingConnection(ws, HOST_ID);
  });

  console.log('[server] started (legacy mode: node server.mjs)');
  startSessionWatcher(wss);
} // end if (isMainModule)
