import net from "node:net";
import path from "node:path";
import { homedir } from "node:os";
import { existsSync, readdirSync, readlinkSync, statSync, realpathSync, readFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { getAgentCapabilities } from "../registry/registry.mjs";

// ── Types ─────────────────────────────────────────────────────────────

export interface HerdrAgentInfo {
  pane_id: string;
  name?: string;
  agent: string;
  agent_status: "working" | "idle" | "blocked" | "done" | "unknown";
  cwd: string;
  foreground_cwd?: string;
  terminal_title?: string;
  terminal_title_stripped?: string;
  workspace_id?: string;
  tab_id?: string;
  agent_session?: {
    source?: string;
    agent?: string;
    kind?: string;
    value?: string;
  };
}

export interface HerdrWorkspaceInfo {
  workspace_id: string;
  number?: number;
  label?: string;
  focused?: boolean;
  pane_count?: number;
  tab_count?: number;
  active_tab_id?: string;
  agent_status?: string;
}

interface HerdrRpcResponse<T = unknown> {
  id?: string;
  result?: T;
  error?: {
    code: string;
    message: string;
  };
}

// ── Low-level Socket Client ───────────────────────────────────────────

let requestCounter = 0;

export type HerdrEndpoint =
  | { kind: "unix"; path: string }
  | { kind: "pipe"; path: string };

export function resolveHerdrEndpoint(): HerdrEndpoint {
  const envPath = process.env.HERDR_SOCKET_PATH?.trim();
  if (envPath) {
    if (envPath.startsWith("\\\\.\\pipe\\") || envPath.startsWith("\\\\?\\pipe\\")) {
      return { kind: "pipe", path: envPath };
    }
    return { kind: "unix", path: envPath };
  }

  const session = process.env.HERDR_SESSION?.trim();
  if (process.platform === "win32") {
    const pipeName = session ? `herdr-${session}` : "herdr";
    return { kind: "pipe", path: `\\\\.\\pipe\\${pipeName}` };
  }

  if (session) {
    return { kind: "unix", path: path.join(homedir(), ".config", "herdr", `${session}.sock`) };
  }
  return { kind: "unix", path: path.join(homedir(), ".config", "herdr", "herdr.sock") };
}

export function getHerdrSocketPath(): string {
  return resolveHerdrEndpoint().path;
}

export interface HerdrProbeResult {
  available: boolean;
  version?: string;
  endpointKind: "unix" | "pipe";
  reason?: string;
  checkedAt: number;
}

let lastProbeResult: HerdrProbeResult | null = null;
let lastProbeEndpointPath = "";
const PROBE_CACHE_TTL_MS = 4000;

function cachedProbeFor(endpointPath: string): HerdrProbeResult | null {
  if (!lastProbeResult) return null;
  if (lastProbeEndpointPath !== endpointPath) return null;
  if (Date.now() - lastProbeResult.checkedAt >= PROBE_CACHE_TTL_MS) return null;
  return lastProbeResult;
}

export async function probeHerdr(force = false): Promise<HerdrProbeResult> {
  const now = Date.now();
  const endpoint = resolveHerdrEndpoint();
  const cached = cachedProbeFor(endpoint.path);
  if (!force && cached) return cached;

  try {
    await sendHerdrRequest("agent.list", {}, 1200);
    lastProbeResult = {
      available: true,
      endpointKind: endpoint.kind,
      checkedAt: now,
    };
  } catch (err: any) {
    lastProbeResult = {
      available: false,
      endpointKind: endpoint.kind,
      reason: err?.message || String(err),
      checkedAt: now,
    };
  }
  lastProbeEndpointPath = endpoint.path;
  return lastProbeResult;
}

export function isHerdrAvailable(): boolean {
  const endpoint = resolveHerdrEndpoint();
  const cached = cachedProbeFor(endpoint.path);
  if (cached) return cached.available;

  if (endpoint.kind === "unix") {
    try {
      return existsSync(endpoint.path);
    } catch {
      return false;
    }
  }
  // Named pipes have no filesystem presence; a negative result is authoritative
  // until the caller runs an explicit probe (which is done on connect).
  return lastProbeEndpointPath === endpoint.path ? (lastProbeResult?.available ?? false) : false;
}

export async function sendHerdrRequest<T = unknown>(
  method: string,
  params: Record<string, unknown> = {},
  timeoutMs = 2000,
): Promise<T> {
  const endpoint = resolveHerdrEndpoint();
  const socketPath = endpoint.path;
  if (endpoint.kind === "unix" && !existsSync(socketPath)) {
    throw new Error(`Herdr socket not found at ${socketPath}`);
  }
  const id = `nexus_req_${++requestCounter}_${Date.now()}`;
  const payload = JSON.stringify({ id, method, params }) + "\n";

  return new Promise<T>((resolve, reject) => {
    let settled = false;
    const client = net.createConnection(socketPath);
    let buffer = "";

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        client.destroy();
        reject(new Error(`Herdr RPC timeout (${timeoutMs}ms) for ${method}`));
      }
    }, timeoutMs);

    client.on("connect", () => {
      client.write(payload);
    });

    client.on("data", (chunk) => {
      buffer += chunk.toString("utf-8");
      if (buffer.includes("\n")) {
        const line = buffer.slice(0, buffer.indexOf("\n")).trim();
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          client.end();
          try {
            const resp = JSON.parse(line) as HerdrRpcResponse<T>;
            if (resp.error) {
              reject(new Error(`Herdr RPC error [${resp.error.code}]: ${resp.error.message}`));
            } else {
              resolve(resp.result as T);
            }
          } catch (err) {
            reject(new Error(`Failed to parse Herdr response: ${String(err)}`));
          }
        }
      }
    });

    client.on("error", (err) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(err);
      }
    });

    client.on("close", () => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(new Error("Connection closed before response received"));
      }
    });
  });
}

// ── Herdr Adapter API ─────────────────────────────────────────────────

export class HerdrAdapter {
  static isAvailable(): boolean {
    return isHerdrAvailable();
  }

  static async probe(force = false): Promise<HerdrProbeResult> {
    return probeHerdr(force);
  }

  static async getIntegrationStatus(): Promise<Record<string, boolean>> {
    const result: Record<string, boolean> = {};
    if (!this.isAvailable()) return result;
    try {
      const stdout = execSync("herdr integration status", { encoding: "utf8", timeout: 3000 });
      for (const line of stdout.split("\n")) {
        const parts = line.split(":");
        if (parts.length >= 2) {
          const name = parts[0].trim();
          const status = parts.slice(1).join(":").trim();
          result[name] = status.startsWith("current");
        }
      }
    } catch {}
    return result;
  }

  static async listWorkspaces(): Promise<HerdrWorkspaceInfo[]> {
    if (!this.isAvailable()) return [];
    try {
      const res = await sendHerdrRequest<{ workspaces: HerdrWorkspaceInfo[] }>("workspace.list", {});
      return res?.workspaces ?? [];
    } catch (err) {
      console.log(`[herdr-adapter] listWorkspaces error: ${String(err)}`);
      return [];
    }
  }

  static async createWorkspace(label?: string, cwd?: string): Promise<string | null> {
    if (!this.isAvailable()) return null;
    try {
      const res = await sendHerdrRequest<{ workspace?: { workspace_id: string } }>("workspace.create", {
        label,
        cwd,
        focus: false,
      });
      return res?.workspace?.workspace_id ?? null;
    } catch (err) {
      console.log(`[herdr-adapter] createWorkspace error: ${String(err)}`);
      return null;
    }
  }

  static async focusWorkspace(workspaceId: string): Promise<void> {
    if (!this.isAvailable()) return;
    await sendHerdrRequest("workspace.focus", { workspace_id: workspaceId });
  }

  static async splitPane(options: {
    workspace_id?: string;
    target_pane_id?: string;
    direction?: "right" | "down";
    cwd?: string;
  }): Promise<string | null> {
    if (!this.isAvailable()) return null;
    const res = await sendHerdrRequest<{ pane?: { pane_id: string } }>("pane.split", {
      direction: options.direction ?? "right",
      workspace_id: options.workspace_id,
      target_pane_id: options.target_pane_id,
      cwd: options.cwd,
      focus: false,
    });
    return res?.pane?.pane_id ?? null;
  }

  static async createTab(options: {
    workspace_id: string;
    label?: string;
    cwd?: string;
  }): Promise<string | null> {
    if (!this.isAvailable()) return null;
    const res = await sendHerdrRequest<{
      tab?: { tab_id: string };
      root_pane?: { pane_id: string };
    }>("tab.create", {
      workspace_id: options.workspace_id,
      label: options.label,
      cwd: options.cwd,
      focus: false,
    });
    return res?.root_pane?.pane_id ?? null;
  }

  static async startAgent(options: {
    pane_id: string;
    kind: string;
    name: string;
    args?: string[];
    retries?: number;
    retryDelayMs?: number;
  }): Promise<boolean> {
    if (!this.isAvailable()) return false;
    // A freshly split pane needs a moment before its shell reaches an
    // interactive prompt; retry only on agent_pane_busy, fail fast otherwise.
    // Herdr agent startup defaults to a 30s timeout; stay above it so a slow
    // start is not misreported as failure (which would leak the new pane).
    const tries = options.retries ?? 12;
    const delayMs = options.retryDelayMs ?? 800;
    let lastErr: unknown = null;
    for (let attempt = 0; attempt <= tries; attempt++) {
      try {
        await sendHerdrRequest("agent.start", {
          pane_id: options.pane_id,
          kind: options.kind,
          name: options.name,
          args: options.args ?? [],
        }, 35000);
        return true;
      } catch (err) {
        lastErr = err;
        if (!String(err).includes("agent_pane_busy") || attempt === tries) throw err;
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }
    throw lastErr;
  }

  static async closePane(paneId: string): Promise<void> {
    await sendHerdrRequest("pane.close", { pane_id: paneId });
  }

  static async focusAgent(target: string): Promise<void> {
    if (!this.isAvailable()) return;
    await sendHerdrRequest("agent.focus", {
      target: target.replace(/^herdr:/, ""),
    });
  }

  static async getProcessInfo(paneId: string): Promise<any> {
    if (!this.isAvailable()) return null;
    const res = await sendHerdrRequest<{ process_info?: any }>("pane.process_info", { pane: paneId });
    return res?.process_info ?? null;
  }

  static async listAgents(): Promise<HerdrAgentInfo[]> {
    if (!this.isAvailable()) return [];
    try {
      const res = await sendHerdrRequest<{ agents: HerdrAgentInfo[] }>("agent.list", {});
      return res?.agents ?? [];
    } catch (err) {
      console.log(`[herdr-adapter] listAgents error: ${String(err)}`);
      return [];
    }
  }

  static async readTerminal(
    target: string,
    lines = 100,
    format: "text" | "ansi" = "text",
  ): Promise<string> {
    if (!this.isAvailable()) return "";
    const res = await sendHerdrRequest<{ read?: { text?: string } }>("agent.read", {
      target,
      source: "recent",
      lines,
      format,
    });
    return res?.read?.text ?? "";
  }

  static async sendPrompt(target: string, text: string): Promise<void> {
    const paneId = target.replace(/^herdr:/, "");
    let lastError: unknown = null;
    for (let attempt = 0; attempt < 10; attempt += 1) {
      try {
        const agent = (await this.listAgents()).find((item) => item.pane_id === paneId);
        if (!agent || agent.agent_status === "unknown") {
          throw new Error("Herdr RPC error [agent_not_ready]: agent for pane " + paneId + " is not ready");
        }
        await sendHerdrRequest("agent.prompt", {
          target: paneId,
          text,
        });
        return;
      } catch (err) {
        lastError = err;
        if (!String(err).includes("[agent_not_ready]") || attempt === 9) throw err;
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
    }
    throw lastError;
  }

  static async sendKeys(target: string, keys: string[]): Promise<void> {
    await sendHerdrRequest("agent.send_keys", {
      target: target.replace(/^herdr:/, ""),
      keys,
    });
  }

  static async resolveSessionFile(paneId: string): Promise<{
    sessionPath?: string;
    sessionId?: string;
    agent: string;
    paneId: string;
    title?: string;
    agentStatus?: HerdrAgentInfo["agent_status"];
    createdAt?: number;
    lastActivity?: number;
  } | null> {
    const targetPaneId = paneId.replace(/^herdr:/, "");
    const agents = await this.listAgents();
    const match = agents.find((a) => a.pane_id === targetPaneId);
    if (!match) return null;

    const targetCwd = match.foreground_cwd || match.cwd;
    let sessionPath: string | undefined;
    const supportsStructuredHistory = getAgentCapabilities(match.agent)?.structuredHistory === true;

    // 1. Absolute highest priority: The .jsonl file actually held open by the active process in this pane!
    // This circumvents stale or outdated agent_session metadata from Herdr IPC when sessions are resumed or switched.
    const activeProcFile = supportsStructuredHistory
      ? findActiveSessionFileForPane(targetPaneId, match.agent)
      : null;
    if (activeProcFile) {
      sessionPath = activeProcFile;
    }

    const ownSession = match.agent_session?.value as string | undefined;
    if (supportsStructuredHistory && !sessionPath && match.agent_session?.kind === "id" && ownSession) {
      // Pane-attributed session id (no path): resolve to its file when present.
      const byId = findSessionFileById(ownSession);
      if (byId) sessionPath = byId;
    } else if (supportsStructuredHistory && !sessionPath && match.agent_session?.kind === "path" && ownSession) {
      // Pane-attributed path is authoritative. When it is not on disk yet
      // (fresh agent, first flush pending) we MUST NOT fall through to
      // cwd-based guessing: in a shared cwd that would replay a stale
      // session into this pane. Terminal mode + upgrade poller cover the gap.
      if (existsSync(ownSession) && ownSession.endsWith(".jsonl")) sessionPath = ownSession;
    } else if (supportsStructuredHistory && match.agent === "omp" && !sessionPath && targetCwd) {
      // No pane attribution at all: guess from cwd, but never reuse files
      // already attributed to OTHER panes sharing this cwd.
      const claimed = new Set(
        agents
          .filter((a) => a.pane_id !== targetPaneId && a.agent_session?.value)
          .map((a) => a.agent_session!.value as string),
      );
      const activeFile = findActiveSessionFileForCwd(targetCwd, claimed);
      if (activeFile) {
        sessionPath = activeFile;
      } else {
        const sessionDir = findSessionDir(targetCwd);
        const newest = findNewestSessionInDir(sessionDir, claimed);
        if (newest) sessionPath = newest;
      }
    }

    if (sessionPath) {
      const base = path.basename(sessionPath, ".jsonl");
      const parts = base.split("_");
      const sessionId = parts.length > 1 ? parts[parts.length - 1] : base;
      const fileTitle = readSessionTitle(sessionPath);
      return {
        sessionPath,
        sessionId,
        agent: match.agent,
        paneId: targetPaneId,
        title: fileTitle || match.terminal_title_stripped || match.terminal_title,
        agentStatus: match.agent_status,
      };
    }

    let fileStat: ReturnType<typeof statSync> | null = null;
    try { fileStat = sessionPath ? statSync(sessionPath) : null; } catch {}
    return {
      agent: match.agent,
      paneId: targetPaneId,
      title: match.terminal_title_stripped || match.terminal_title,
      agentStatus: match.agent_status,
      createdAt: fileStat?.birthtimeMs || fileStat?.ctimeMs,
      lastActivity: fileStat?.mtimeMs,
    };
  }
}

// ── Streamer & Output Delta Synchronizer ──────────────────────────────

interface StreamSession {
  paneId: string;
  lastContent: string;
  lastStatus: string;
  subscribers: Set<(msg: unknown) => void>;
  timer: NodeJS.Timeout | null;
  pollCount: number;
}

const activeStreams = new Map<string, StreamSession>();

export class HerdrStreamer {
  static stop(paneId: string): void {
    const session = activeStreams.get(paneId);
    if (session?.timer) clearInterval(session.timer);
    activeStreams.delete(paneId);
  }

  /**
   * Subscribe a client callback to live updates of a Herdr pane.
   */
  static subscribe(paneId: string, listener: (msg: unknown) => void): void {
    let sess = activeStreams.get(paneId);
    if (!sess) {
      sess = {
        paneId,
        lastContent: "",
        lastStatus: "unknown",
        subscribers: new Set(),
        timer: null,
        pollCount: 0,
      };
      activeStreams.set(paneId, sess);
      this.startPolling(sess);
    }
    sess.subscribers.add(listener);
  }

  /**
   * Unsubscribe a client callback. Automatically cleans up timer and memory when subscribers reach 0.
   */
  static unsubscribe(paneId: string, listener: (msg: unknown) => void): void {
    const sess = activeStreams.get(paneId);
    if (!sess) return;
    sess.subscribers.delete(listener);
    if (sess.subscribers.size === 0) {
      if (sess.timer) {
        clearInterval(sess.timer);
        sess.timer = null;
      }
      activeStreams.delete(paneId);
      console.log(`[herdr-streamer] stopped watching pane ${paneId} (no subscribers)`);
    }
  }

  /**
   * Seed the initial content of a session so first poll only computes new deltas.
   */
  static seedContent(paneId: string, initialContent: string): void {
    const sess = activeStreams.get(paneId);
    if (sess) {
      sess.lastContent = initialContent;
    }
  }

  private static startPolling(sess: StreamSession): void {
    const pollInterval = 300; // 300ms 黄金刷新率，平滑流畅且不占用 CPU
    sess.timer = setInterval(async () => {
      if (sess.subscribers.size === 0) {
        if (sess.timer) clearInterval(sess.timer);
        activeStreams.delete(sess.paneId);
        return;
      }

      try {
        const raw = await HerdrAdapter.readTerminal(sess.paneId, 100, "text");
        const text = cleanTerminalText(raw);
        if (sess.lastContent === "") {
          sess.lastContent = text;
        } else if (text !== sess.lastContent) {
          const delta = computeTerminalDelta(sess.lastContent, text);

          if (delta.length > 0 && delta.trim().length > 0) {
            sess.lastContent = text;
            const eventMsg = {
              type: "agent_event",
              sessionId: `herdr:${sess.paneId}`,
              event: {
                sessionUpdate: "agent_message_chunk",
                content: {
                  type: "text",
                  text: delta,
                },
              },
            };
            for (const sub of sess.subscribers) {
              try {
                sub(eventMsg);
              } catch {
                // ignore failed subscriber
              }
            }
          }
        }

        // Check status change every 4 polls (2 seconds)
        sess.pollCount += 1;
        if (sess.pollCount % 4 === 0) {
          const agents = await HerdrAdapter.listAgents();
          const info = agents.find((a) => a.pane_id === sess.paneId);
          if (info && info.agent_status !== sess.lastStatus) {
            const oldStatus = sess.lastStatus;
            sess.lastStatus = info.agent_status;
            const statusMsg = {
              type: "session_status",
              sessionId: `herdr:${sess.paneId}`,
              status: info.agent_status,
            };
            for (const sub of sess.subscribers) {
              try { sub(statusMsg); } catch { /* closed subscriber */ }
            }
            if (oldStatus === "working" && (info.agent_status === "idle" || info.agent_status === "done")) {
              const turnEndMsg = {
                type: "turn_ended",
                sessionId: `herdr:${sess.paneId}`,
              };
              for (const sub of sess.subscribers) {
                try {
                  sub(turnEndMsg);
                } catch { /* ok */ }
              }
            }
          }
        }
      } catch (err) {
        // Silent error on individual poll cycle
      }
    }, pollInterval);
  }
}

/**
 * Cleans ANSI escape codes and raw carriage returns from terminal output.
 */
export function cleanTerminalText(str: string): string {
  return str
    .replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "")
    .replace(/\x1b\].*?(\x07|\x1b\\)/g, "")
    .replace(/\r/g, "");
}

/**
 * Computes new appended text using high-performance line-based diff.
 */
export function computeTerminalDelta(oldText: string, newText: string): string {
  if (!oldText) return newText;
  if (newText === oldText) return "";
  if (newText.startsWith(oldText)) {
    return newText.slice(oldText.length);
  }

  const oldLines = oldText.split("\n");
  const newLines = newText.split("\n");

  let matchIdx = 0;
  const maxCheck = Math.min(oldLines.length, newLines.length);
  while (matchIdx < maxCheck && oldLines[matchIdx] === newLines[matchIdx]) {
    matchIdx++;
  }

  if (matchIdx < newLines.length) {
    if (matchIdx > 0 && matchIdx === oldLines.length && newLines[matchIdx - 1]?.startsWith(oldLines[matchIdx - 1])) {
      const partial = newLines[matchIdx - 1].slice(oldLines[matchIdx - 1].length);
      const remaining = newLines.slice(matchIdx).join("\n");
      return partial + (remaining ? "\n" + remaining : "");
    }
    return newLines.slice(matchIdx).join("\n");
  }

  return "";
}

function findActiveSessionFileForCwd(targetCwd: string, exclude?: Set<string>): string | null {
  if (process.platform !== "linux" || !existsSync("/proc")) {
    return null;
  }
  try {
    const pids = execSync('pgrep -f "bun .*/omp"', { encoding: "utf8" }).trim().split("\n").filter(Boolean);
    const resolvedTarget = realpathSync(targetCwd);

    for (const pid of pids) {
      try {
        const procCwd = realpathSync(`/proc/${pid}/cwd`);
        if (procCwd === resolvedTarget) {
          const fds = readdirSync(`/proc/${pid}/fd`);
          for (const fd of fds) {
            try {
              const link = readlinkSync(`/proc/${pid}/fd/${fd}`);
              if (link.endsWith(".jsonl") && existsSync(link) && !exclude?.has(link)) {
                return link;
              }
            } catch {}
          }
        }
      } catch {}
    }
  } catch {}
  return null;
}

function isStructuredSessionPath(agent: string, candidate: string): boolean {
  const resolved = path.resolve(candidate);
  if (agent === "omp") {
    return resolved.includes(path.join(".omp", "agent", "sessions")) || resolved.endsWith(".jsonl");
  }
  if (agent === "codex") {
    return resolved.includes(path.join(".codex", "sessions"))
      && path.basename(resolved).startsWith("rollout-");
  }
  return false;
}

function findActiveSessionFileForPane(targetPaneId: string, agent: string): string | null {
  if (process.platform !== "linux" || !existsSync("/proc")) {
    return null;
  }
  try {
    const pids = readdirSync("/proc").filter((p) => /^\d+$/.test(p));
    for (const pid of pids) {
      try {
        const environ = readFileSync(`/proc/${pid}/environ`, "utf8").split("\0");
        const hasPane = environ.some((e) => e === `HERDR_PANE_ID=${targetPaneId}`);
        if (!hasPane) continue;

        const fdDir = `/proc/${pid}/fd`;
        if (!existsSync(fdDir)) continue;
        const fds = readdirSync(fdDir);
        for (const fd of fds) {
          try {
            const link = readlinkSync(`${fdDir}/${fd}`);
            if (link.endsWith(".jsonl") && existsSync(link) && isStructuredSessionPath(agent, link)) {
              return link;
            }
          } catch {}
        }
      } catch {}
    }
  } catch {}
  return null;
}

export type HerdrEventListener = (event: { type?: string; event?: string; [key: string]: any }) => void;

export class HerdrEventBus {
  private static client: net.Socket | null = null;
  private static listeners = new Set<HerdrEventListener>();
  private static reconnectTimer: NodeJS.Timeout | null = null;
  private static buffer = "";

  static start(): void {
    if (this.client) return;
    this.connect();
  }

  static addListener(listener: HerdrEventListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private static connect(): void {
    const endpoint = resolveHerdrEndpoint();
    if (endpoint.kind === "unix" && !existsSync(endpoint.path)) {
      this.scheduleReconnect();
      return;
    }

    try {
      const sock = net.createConnection(endpoint.path);
      this.client = sock;
      sock.unref();

      sock.on("connect", () => {
        const subReq = {
          jsonrpc: "2.0",
          id: `sub_${Date.now()}`,
          method: "events.subscribe",
          params: {
            subscriptions: [
              { type: "pane.agent_status_changed" },
              { type: "pane.agent_detected" },
              { type: "workspace.created" },
              { type: "workspace.updated" },
              { type: "workspace.closed" },
              { type: "pane.created" },
              { type: "pane.closed" },
            ],
          },
        };
        sock.write(JSON.stringify(subReq) + "\n");
      });

      sock.on("data", (chunk) => {
        this.buffer += chunk.toString("utf8");
        const lines = this.buffer.split("\n");
        this.buffer = lines.pop() ?? "";
        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            const parsed = JSON.parse(line);
            if (parsed.result?.type === "subscription_started") continue;
            const ev = parsed.event ? parsed : (parsed.params || parsed);
            for (const l of this.listeners) {
              try { l(ev); } catch (err) { console.error("[herdr-event-bus] listener error:", err); }
            }
          } catch {}
        }
      });

      sock.on("error", () => {
        sock.destroy();
      });

      sock.on("close", () => {
        this.client = null;
        this.scheduleReconnect();
      });
    } catch {
      this.scheduleReconnect();
    }
  }

  private static scheduleReconnect(): void {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer?.unref();
      this.reconnectTimer = null;
      this.connect();
    }, 3000);
  }

  static stop(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.client) {
      this.client.destroy();
      this.client = null;
    }
  }
}

function findSessionDir(cwd: string): string | null {
  const baseDir = path.join(homedir(), ".omp", "agent", "sessions");
  if (!existsSync(baseDir)) return null;
  const dirs = readdirSync(baseDir);
  const norm = path.resolve(cwd);
  for (const d of dirs) {
    const cleaned = d.replace(/^-+|-+$/g, "").replace(/-/g, "/");
    if ("/" + cleaned === norm || cleaned === norm.replace(/^\//, "")) {
      return path.join(baseDir, d);
    }
  }
  return null;
}

function findNewestSessionInDir(dir: string | null, exclude?: Set<string>): string | null {
  if (!dir || !existsSync(dir)) return null;
  const files = readdirSync(dir).filter((f) => f.endsWith(".jsonl") && !exclude?.has(path.join(dir, f)));
  if (files.length === 0) return null;
  files.sort((a, b) => statSync(path.join(dir, b)).mtimeMs - statSync(path.join(dir, a)).mtimeMs);
  return path.join(dir, files[0]);
}

export function readSessionTitle(filePath: string): string | null {
  try {
    const content = readFileSync(filePath, "utf8");
    const lines = content.split("\n");
    let title: string | null = null;
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const obj = JSON.parse(line);
        if (obj.type === "title" || obj.type === "title_change") {
          title = obj.title;
        }
      } catch {}
    }
    return title;
  } catch {
    return null;
  }
}

export function findSessionFileById(sessionId: string): string | null {
  const baseDir = path.join(homedir(), ".omp", "agent", "sessions");
  if (!existsSync(baseDir)) return null;
  try {
    const dirs = readdirSync(baseDir);
    for (const d of dirs) {
      const dirPath = path.join(baseDir, d);
      try {
        if (!statSync(dirPath).isDirectory()) continue;
        const files = readdirSync(dirPath);
        for (const f of files) {
          if (f.endsWith(".jsonl") && f.includes(sessionId)) {
            return path.join(dirPath, f);
          }
        }
      } catch {}
    }
  } catch {}
  return null;
}
