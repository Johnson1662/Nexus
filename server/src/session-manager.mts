import kill from "tree-kill";
import { spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, realpathSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { WebSocket } from "ws";
import { AcpClient, type AcpClientCallbacks } from "./acp/client.mjs";
import type { RequestPermissionRequest, RequestPermissionResponse } from "@agentclientprotocol/sdk";
import type { SessionState } from "./acp/types.mjs";
import { resolveAgentInfo } from "./agents-store.mjs";
import { resolveWorkspacePath } from "./path-utils.mjs";
import { createAcpCallbacks } from "./acp-callbacks.mjs";
import { getLastModel, setLastModel } from "./prefs.mjs";
import { recordToolCallIds } from "./tool-call-map.mjs";
import { extractModelList, setCachedModelList, invalidateModelListCache } from "./model-list.mjs";


// ── Constants ────────────────────────────────────────────────────
const MAX_TOOLCALL_IDS = 500;
const IDLE_TIMEOUT_MS = 15 * 60 * 1_000;
const MAX_ACP_PROCESSES = 5;
const IDLE_CLEANUP_INTERVAL_MS = 30_000;
const MAX_MESSAGE_BUFFER = 500;
const PROMPT_TIMEOUT = 300_000; // 5 minutes sliding inactivity
const AGENT_INITIALIZE_TIMEOUT_MS = 30_000;

export type SessionOwnerErrorCode =
  | "SESSION_NOT_FOUND"
  | "SESSION_NOT_OWNER"
  | "SESSION_RECLAIM_REQUIRED";

export class SessionOwnerError extends Error {
  constructor(public readonly code: SessionOwnerErrorCode, message: string) {
    super(message);
    this.name = "SessionOwnerError";
  }
}

function resolveAgentLaunch(agent: string): { cmd: string; args: string[]; env: Record<string, string> } {
  const resolved = resolveAgentInfo(agent);
  if (!resolved || !resolved.cmd || !Array.isArray(resolved.args) || resolved.args.some(arg => typeof arg !== "string")) {
    throw new Error(`invalid or unavailable agent: ${agent}`);
  }
  return { cmd: resolved.cmd, args: [...resolved.args], env: { ...resolved.env } };
}

function spawnAgentProcess(agent: string, cwd: string): ChildProcess {
  const launch = resolveAgentLaunch(agent);
  return spawn(launch.cmd, launch.args, {
    cwd,
    env: { ...process.env, ...launch.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    shell: false,
    windowsHide: true,
  });
}

async function initializeWithTimeout(client: AcpClient, proc: ChildProcess): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let rejectProcessError: (error: Error) => void = () => {};
  const onProcessError = (error: Error) => rejectProcessError(error);
  const processError = new Promise<never>((_resolve, reject) => {
    rejectProcessError = (error: Error) => reject(new Error(`agent process failed: ${error.message}`));
    proc.once("error", onProcessError);
  });
  const timeout = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new Error("agent initialize timeout")), AGENT_INITIALIZE_TIMEOUT_MS);
  });
  try {
    await Promise.race([client.initialize(), processError, timeout]);
  } finally {
    clearTimeout(timer);
    proc.removeListener("error", onProcessError);
  }
}

const MODEL_ERROR_PATTERNS: RegExp[] = [
  /rate limit/i, /quota/i, /429/i, /402/i, /insufficient_quota/i,
  /resource.*exhausted/i, /too many request/i, /billing/i,
  /credit.*exhausted/i, /payment required/i, /model.*not.*found/i,
  /model.*unavailable/i, /api.*error/i, /auth.*error/i,
  /unauthorized/i, /forbidden/i, /403/i, /401/i, /\b5[0-9]{2}\b/i,
];

// ── DI Interface ─────────────────────────────────────────────────
/** Inversion-of-control seam for testability — overrides AcpClient construction. */
export interface AcpClientFactory {
  create(proc: ChildProcess, callbacks: AcpClientCallbacks): AcpClient;
}

// ── Params Interface ──────────────────────────────────────────────
export interface CreateSessionParams {
  agent?: string;
  cwd?: string;
  model?: string;
  prompt?: string;
  /** Pre-existing ACP session to attach to (load/resume). */
  sessionId?: string;
  lastMessageId?: string;
  /** Session creation strategy. */
  mode?: "create" | "load" | "resume";
}

// ── SessionManager ────────────────────────────────────────────────
/**
 * Deep module owning the process-pool lifecycle, prompt dispatch with
 * error-pattern detection, idle eviction, and replay-buffer cursor sync.
 *
 * Interface is 8 public methods + constructor. All complexity (LRU eviction,
 * sliding inactivity timeout, stderr streaming, model error heuristics)
 * is hidden behind those seams.
 */
export class SessionManager {
  private sessions = new Map<string, SessionState>();
  private sessionSeqCounter = new Map<string, number>();
  private wsOpQueues = new Map<import("ws").WebSocket, Promise<unknown>>();
  private pendingCreates = new Map<import("ws").WebSocket, Promise<SessionState>>();
  private transportIds = new WeakMap<object, string>();
  private idleCleanupTimer: ReturnType<typeof setInterval> | null = null;
  private clientFactory: AcpClientFactory;

  constructor(factory?: AcpClientFactory) {
    this.clientFactory = factory ?? {
      create: (proc, callbacks) => new AcpClient(proc, callbacks),
    };
  }

  private transportIdentity(transport: WebSocket): string {
    const object = transport as unknown as object;
    let id = this.transportIds.get(object);
    if (!id) {
      id = randomUUID();
      this.transportIds.set(object, id);
    }
    return id;
  }

  private claimSession(sess: SessionState, transport: WebSocket): SessionState {
    sess.ownerTransport = transport;
    sess.ownerId = this.transportIdentity(transport);
    sess.ws = transport;
    sess.orphanedAt = null;
    return sess;
  }

  /** The one owner check used by every sessionId operation. */
  public assertOwner(sessionId: string, transport: WebSocket): SessionState {
    const sess = this.sessions.get(sessionId);
    if (!sess) throw new SessionOwnerError("SESSION_NOT_FOUND", "session not found");
    if (sess.ownerTransport !== transport) {
      throw new SessionOwnerError("SESSION_NOT_OWNER", "session is owned by another connection");
    }
    return sess;
  }

  // ═══════════════════════════════════════════════════════════════
  // PUBLIC API — 8 methods
  // ═══════════════════════════════════════════════════════════════

  /** ── getOrCreate ─────────────────────────────────────────────
   *  Return the session matching `params.sessionId` if already alive,
   *  or spawn a new ACP agent process, initialise the ACP protocol,
   *  and register the session in the pool.
   */
  async getOrCreate(ws: WebSocket, params: CreateSessionParams): Promise<SessionState> {
    const inFlight = this.pendingCreates.get(ws);
    if (inFlight) return inFlight;
    const pending = this.getOrCreateInternal(ws, params);
    this.pendingCreates.set(ws, pending);
    try {
      return await pending;
    } finally {
      if (this.pendingCreates.get(ws) === pending) this.pendingCreates.delete(ws);
    }
  }

  private async getOrCreateInternal(ws: WebSocket, params: CreateSessionParams): Promise<SessionState> {
    const {
      agent = "opencode",
      cwd,
      model,
      mode = "create",
    } = params;
    const targetSessionId = params.sessionId;

    // Re-use existing session if still live
    if (targetSessionId) {
      const existing = this.sessions.get(targetSessionId);
      if (existing) {
        if (existing.ownerTransport && existing.ownerTransport !== ws) {
          throw new SessionOwnerError("SESSION_NOT_OWNER", "session is owned by another connection");
        }
        if (!existing.ownerTransport) {
          if (existing.orphanedAt === null || (mode !== "load" && mode !== "resume")) {
            throw new SessionOwnerError("SESSION_RECLAIM_REQUIRED", "session reclaim requires an explicit load, resume, or sync request");
          }
          this.claimSession(existing, ws);
        } else {
          existing.ws = ws;
          existing.ownerId = this.transportIdentity(ws);
        }
        this.updateSessionActivity(targetSessionId);
        if (mode === "load" || mode === "resume") {
          if (!existing.loadInFlight) {
            existing.loadInFlight = (async () => {
              if (mode === "load") {
                await existing.client.loadSession(targetSessionId, existing.cwd);
              } else {
                await existing.client.resumeSession(targetSessionId, existing.cwd);
              }
            })().finally(() => {
              existing.loadInFlight = undefined;
            });
          }
          await existing.loadInFlight;
        }
        return existing;
      }
    }

    // Orphan any previous sessions belonging to this WS
    this.cleanupWsSessions(ws);

    const launch = resolveAgentLaunch(agent);
    const ANYWHERE_DIR = join(homedir(), ".nexus");
    mkdirSync(ANYWHERE_DIR, { recursive: true });
    const requestedCwd = resolveWorkspacePath(cwd);
    const resolvedCwd = requestedCwd && existsSync(requestedCwd) && statSync(requestedCwd).isDirectory()
      ? realpathSync(requestedCwd)
      : ANYWHERE_DIR;
    const proc = spawn(launch.cmd, launch.args, {
      cwd: resolvedCwd,
      env: { ...process.env, ...launch.env, FORCE_COLOR: "0", NO_COLOR: "1" },
      stdio: ["pipe", "pipe", "pipe"],
      shell: false,
      windowsHide: true,
    });

    // `sessionId` is the bridge-wide key; for new sessions it is set after
    // the ACP createSession call.  We store the partial object early so
    // event handlers can find it via the legacy module-level map.
    // (let — reassigned after ACP init so callback closures see the real ID.)
    let sessionId = targetSessionId ?? "";
    const wsRef = ws;

    const sess: SessionState = {
      ws: wsRef,
      ownerTransport: wsRef,
      ownerId: this.transportIdentity(wsRef),
      client: null!, // assigned below
      sessionId: "",
      cwd: resolvedCwd,
      process: proc,
      agent,
      pendingPermissions: new Map(),
      terminals: new Map(),
      restartCount: 0,
      toolCallIdMap: new Map(),
      turnActive: false,
      lastActivity: Date.now(),
      orphanedAt: null,
      messageBuffer: [],
    };

    // ── Build ACP callbacks ────────────────────────────────────
    const callbacks: AcpClientCallbacks = {
      onSessionUpdate: async (update) => {
        const s = this.sessions.get(sessionId);
        if (s) {
          recordToolCallIds(s, update.update);
          this.updateSessionActivity(sessionId);
        }
        const eventPayload = {
          type: "agent_event",
          sessionId,
          event: update.update,
        };
        let wsPayload: object;
        try {
          wsPayload = this.bufferAgentEvent(sessionId, eventPayload) ?? eventPayload;
        } catch { /* buffer full — discard */
          wsPayload = eventPayload;
        }
        try {
          // orphan（s 存在但 ownerTransport 为 null）时事件已缓冲，等 reclaim 后 sync 补齐，
          // 不再向旧连接实时发送；创建初期（map 无此 key）仍发当前 wsRef。
          const s = this.sessions.get(sessionId);
          const currentWs = s ? s.ownerTransport : wsRef;
          if (currentWs) currentWs.send(JSON.stringify(wsPayload));
        } catch { /* WS disconnected — event buffered */ }
      },
      onPermissionRequest: this.buildPermissionRequestCallback(wsRef, () => sessionId),
      ...createAcpCallbacks({
        getSessionId: () => sessionId,
        cwd: resolvedCwd,
        toolCallIdMap: sess.toolCallIdMap,
      }),
    };

    const client = this.clientFactory.create(proc, callbacks);
    sess.client = client;

    // Register early in the local map so createAcpCallbacks's
    // getSession() can find this session once ACP init creates the ID.
    if (targetSessionId) {
      this.sessions.set(targetSessionId, sess);
    }

    // ── Process lifecycle listeners ────────────────────────────
    proc.stderr.on("data", (chunk: Buffer) => {
      console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    });
    proc.on("error", (err: Error) => {
      console.log(`[session-manager] ${agent} process error: ${err.message}`);
      try {
        sess.ws?.send(JSON.stringify({ type: "error", sessionId, code: "AGENT_SPAWN_FAILED", text: `Agent process failed: ${err.message}` }));
      } catch { /* WS gone */ }
      if (sessionId) {
        const current = this.sessions.get(sessionId);
        if (current === sess) {
          this.killTerminalProcesses(sess);
          this.cancelPendingPermissions(sess);
          this.sessions.delete(sessionId);
          this.sessionSeqCounter.delete(sessionId);
        }
      }
    });
    proc.on("exit", (code) => {
      console.log(`[server] ${sessionId} process exited with code ${code}`);
      if (sessionId) {
        const s = this.sessions.get(sessionId);
        if (s) {
          this.killTerminalProcesses(s);
          this.cancelPendingPermissions(s);
          this.sessions.delete(sessionId);
          this.sessionSeqCounter.delete(sessionId);
        }
      }
    });

    // ── ACP initialisation ─────────────────────────────────────
    try {
      await initializeWithTimeout(client, proc);
      if (mode === "load" && targetSessionId) {
        sess.loadInFlight = (async () => {
          await client.loadSession(targetSessionId, resolvedCwd);
        })().finally(() => {
          sess.loadInFlight = undefined;
        });
        await sess.loadInFlight;
        sessionId = targetSessionId;
      } else if (mode === "resume" && targetSessionId) {
        sess.loadInFlight = (async () => {
          await client.resumeSession(targetSessionId, resolvedCwd);
        })().finally(() => {
          sess.loadInFlight = undefined;
        });
        await sess.loadInFlight;
        sessionId = targetSessionId;
      } else {
        const result = await client.createSession(resolvedCwd);
        sessionId = result.sessionId;
      }
    } catch (err: unknown) {
      // Tear down on init failure
      try { client.destroy(); } catch { /* ok */ }
      if (!proc.killed) {
        try { kill(proc.pid!, "SIGTERM"); } catch { /* ok */ }
      }
      throw err;
    }

    // Finalise session identity
    sess.sessionId = sessionId;

    // Apply model if provided or restore last used
    const activeModel = model || getLastModel(agent);
    if (activeModel) {
      try {
        await client.setSessionModel(sessionId, activeModel);
        setLastModel(agent, activeModel);
      } catch (errModel: any) {
        console.log(`[server] setSessionModel failed: ${errModel.message}`);
      }
    }

    // Seed cached model list from initialised client
    try {
      const models = extractModelList(client);
      if (models) setCachedModelList(agent, resolvedCwd, models);
    } catch { /* best-effort */ }

    // Register in the local map under the final key
    this.sessions.set(sessionId, sess);
    this.updateSessionActivity(sessionId);

    // Lazy-start idle cleanup timer
    this.ensureIdleCleanupRunning();

    console.log(`[session-manager] session created: ${sessionId.slice(0, 20)}… agent=${agent}`);

    return sess;
  }

  /** Send a payload to the session's CURRENT owner transport.
   *  Resolved at send time so a stale turn can never leak
   *  turn_ended/error frames onto a WebSocket that a newer session
   *  has since reclaimed. */
  private sendToOwner(sessionId: string, payload: object): void {
    const owner = this.sessions.get(sessionId)?.ownerTransport;
    if (!owner) return;
    try {
      owner.send(JSON.stringify(payload));
    } catch { /* WS gone */ }
  }

  /** ── beginPrompt ────────────────────────────────────────────
   *  Atomically claim the turn for a prompt — synchronous validation
   *  (ownership, turn-active, initialized). On success the caller
   *  MUST send `input_ack` immediately, then run the returned handle.
   *  Throws SessionOwnerError / Error: the caller sends the error
   *  reply back to the requesting transport.
   */
  beginPrompt(
    sessionId: string,
    text: string,
    ownerTransport: WebSocket,
  ): { run: () => Promise<void> } {
    const sess = this.assertOwner(sessionId, ownerTransport);
    if (sess.turnActive) {
      throw new Error("session turn already active");
    }
    if (!sess.sessionId) {
      throw new SessionOwnerError("SESSION_NOT_FOUND", "session is not initialized");
    }
    // Claim the turn BEFORE any await so concurrent inputs are
    // rejected atomically (input_ack is only sent on success).
    sess.turnActive = true;
    this.updateSessionActivity(sessionId);
    return {
      run: () => this.runPromptTurn(sessionId, text).catch((err: unknown) => {
        const msg = err instanceof Error ? err.message : String(err);
        console.log(`[session-manager] prompt turn error: ${msg}`);
        this.finishTurn(sessionId, "error");
        this.sendToOwner(sessionId, {
          type: "error",
          sessionId,
          text: `Agent error: ${msg}`,
        });
      }),
    };
  }

  /** ── runPromptTurn ──────────────────────────────────────────
   *  Async prompt body: auto-restart of a dead ACP connection,
   *  keep-alive heartbeat, sliding inactivity timeout and stderr
   *  model-error monitoring. All turn_ended / error frames go
   *  through sendToOwner — never a captured transport.
   */
  private async runPromptTurn(sessionId: string, text: string): Promise<void> {
    // Auto-recover dead ACP connection by restarting the session
    let liveSess = this.sessions.get(sessionId);
    if (!liveSess || !liveSess.sessionId || !liveSess.client) {
      return;
    }
    if (!liveSess.client.connected) {
      const ok = await this.restartSession(sessionId);
      if (!ok) {
        liveSess = this.sessions.get(sessionId);
        if (liveSess) {
          this.finishTurn(sessionId, "error");
        }
        this.sendToOwner(sessionId, {
          type: "error",
          sessionId,
          text: `Failed to restart session: ${sessionId}`,
        });
        return;
      }
    }

    // Guard: session may have been cleaned up during restart
    liveSess = this.sessions.get(sessionId);
    if (!liveSess || !liveSess.sessionId || !liveSess.client) {
      return;
    }

    const startTime = Date.now();
    let timedOut = false;
    let errorDetected = false;

    // Heartbeat keep-alive during prompt
    const keepAlive = setInterval(() => {
      if (timedOut || errorDetected) return;
      this.sendToOwner(sessionId, { type: "heartbeat", sessionId, ts: Date.now() });
    }, 3_000);

    // ── stderr model-error monitoring ─────────────────────────
    let stderrHandler: ((chunk: Buffer) => void) | null = null;
    if (liveSess.process?.stderr) {
      stderrHandler = (chunk: Buffer) => {
        if (errorDetected || timedOut) return;
        const stderrText = chunk.toString();
        for (const pattern of MODEL_ERROR_PATTERNS) {
          if (!pattern.test(stderrText)) continue;
          errorDetected = true;
          clearInterval(keepAlive);
          clearTimeout(timer);
          console.log(
            `[session-manager] model error detected: ${stderrText.slice(0, 200)}`,
          );
          liveSess.client.cancel(liveSess.sessionId!).catch(() => {});
          this.finishTurn(sessionId, "error");
          this.sendToOwner(sessionId, {
            type: "error",
            sessionId,
            text: `Model error: ${stderrText.slice(0, 300).trim()}`,
          });
          break;
        }
      };
      liveSess.process.stderr.on("data", stderrHandler);
    }

    // ── Sliding inactivity timeout (5 min) ────────────────────
    let timer: ReturnType<typeof setTimeout> | undefined;

    const resetInactivityTimer = () => {
      if (timedOut || errorDetected) return;
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (errorDetected) return;
        timedOut = true;
        clearInterval(keepAlive);
        console.log(
          `[session-manager] prompt INACTIVITY TIMEOUT (5min) after ${Date.now() - startTime}ms for ${sessionId}`,
        );
        if (stderrHandler && liveSess.process?.stderr) {
          try {
            liveSess.process.stderr.removeListener("data", stderrHandler);
          } catch { /* ok */ }
        }
        liveSess.client.cancel(liveSess.sessionId!).catch(() => {});
        this.finishTurn(sessionId, "timeout");
        this.sendToOwner(sessionId, {
          type: "error",
          sessionId,
          text: "[Timeout] 连续 5 分钟未收到任何输出或工具回调。",
        });
      }, PROMPT_TIMEOUT);
    };

    liveSess.resetTimeout = resetInactivityTimer;
    resetInactivityTimer();

    // ── Issue ACP prompt ──────────────────────────────────────
    try {
      const result = await liveSess.client.prompt(liveSess.sessionId, text);

      if (timedOut || errorDetected) return;

      clearInterval(keepAlive);
      clearTimeout(timer);
      if (stderrHandler && liveSess.process?.stderr) {
        try {
          liveSess.process.stderr.removeListener("data", stderrHandler);
        } catch { /* ok */ }
      }
      console.log(
        `[session-manager] turn ended after ${Math.floor((Date.now() - startTime) / 1_000)}s: ${result?.stopReason}`,
      );
      this.finishTurn(sessionId, result?.stopReason);
    } catch (err: unknown) {
      if (timedOut || errorDetected) return;

      clearInterval(keepAlive);
      clearTimeout(timer);
      if (stderrHandler && liveSess.process?.stderr) {
        try {
          liveSess.process.stderr.removeListener("data", stderrHandler);
        } catch { /* ok */ }
      }
      const msg = err instanceof Error ? err.message : String(err);
      console.log(
        `[session-manager] prompt error after ${Math.floor((Date.now() - startTime) / 1_000)}s: ${msg}`,
      );
      this.finishTurn(sessionId, "error");
      const displayMsg =
        msg.includes("closed") || msg.includes("abort")
          ? "[Session expired] Send a message to auto-restart."
          : `Agent error: ${msg}`;
      this.sendToOwner(sessionId, {
        type: "error",
        sessionId,
        text: displayMsg,
      });
    }
  }

  /** ── replayBuffer ───────────────────────────────────────────
   *  Return buffered agent events after `lastMessageId` for cursor
   *  sync replay.
   */
  replayBuffer(
    sessionId: string,
    lastMessageId: string,
    ownerTransport?: WebSocket,
  ): {
    entries: Array<{
      messageId: string;
      payload: string;
      timestamp: number;
    }>;
    overflow: boolean;
  } {
    const sess = ownerTransport
      ? this.assertOwner(sessionId, ownerTransport)
      : this.sessions.get(sessionId);
    if (!sess) return { entries: [], overflow: false };

    let lastSeq = 0;
    if (lastMessageId) {
      const parts = lastMessageId.split(":");
      lastSeq = parseInt(parts[parts.length - 1]) || 0;
    }

    let firstBufferedSeq = 0;
    if (sess.messageBuffer.length > 0) {
      const firstParts = sess.messageBuffer[0].messageId.split(":");
      firstBufferedSeq = parseInt(firstParts[firstParts.length - 1]) || 0;
    }

    const overflow =
      lastSeq > 0 &&
      firstBufferedSeq > 0 &&
      lastSeq < firstBufferedSeq - 1;

    const entries = sess.messageBuffer.filter((m) => {
      const mParts = m.messageId.split(":");
      const mSeq = parseInt(mParts[mParts.length - 1]) || 0;
      return mSeq > lastSeq;
    });

    return { entries, overflow };
  }

  /** ── evictIdle ──────────────────────────────────────────────
   *  Run one round of idle-eviction and LRU pool-limit enforcement.
   *  Orphaned sessions idle for 15+ minutes are killed; if the total
   *  process count exceeds `MAX_ACP_PROCESSES`, the oldest idle
   *  sessions are evicted (active-turn sessions are never touched).
   */
  evictIdle(): void {
    const now = Date.now();

    // ── Idle timeout eviction ──────────────────────────────────
    const toRemove: string[] = [];
    for (const [id, sess] of this.sessions) {
      if (sess.turnActive) continue;
      if (sess.orphanedAt === null) continue;
      const idleFor = now - sess.lastActivity;
      if (idleFor > IDLE_TIMEOUT_MS) {
        toRemove.push(id);
      }
    }

    for (const id of toRemove) {
      const sess = this.sessions.get(id);
      if (!sess) continue;
      console.log(
        `[session-manager] idle timeout: killing session ${id.slice(0, 20)} (idle ${Math.floor((now - sess.lastActivity) / 1_000)}s)`,
      );
      this.killTerminalProcesses(sess);
      this.killSessionProcess(sess);
      this.cancelPendingPermissions(sess);
      this.sessions.delete(id);
      this.sessionSeqCounter.delete(id);
    }

    if (toRemove.length > 0) {
      console.log(
        `[session-manager] idle cleanup removed ${toRemove.length} sessions`,
      );
    }

    // ── LRU process-pool limit enforcement ─────────────────────
    this.enforceProcessPoolLimit();
  }

  /** ── close ──────────────────────────────────────────────────
   *  Close an ACP session, kill its process, and remove from the
   *  pool.  Throws if the session is not found.
   */
  async close(sessionId: string, ownerTransport: WebSocket): Promise<void> {
    const sess = this.assertOwner(sessionId, ownerTransport);
    this.cancelPendingPermissions(sess);

    try {
      await sess.client.closeSession(sess.sessionId);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.log(`[session-manager] closeSession error: ${msg}`);
    }

    this.killSessionProcess(sess);
    this.killTerminalProcesses(sess);
    this.sessions.delete(sessionId);
    this.sessionSeqCounter.delete(sessionId);

    console.log(`[session-manager] session closed: ${sessionId.slice(0, 20)}`);
  }

  /** ── cancel ─────────────────────────────────────────────────
   *  Cancel the current turn on an ACP session (no-op if missing).
   */
  cancel(sessionId: string, ownerTransport: WebSocket): void {
    const sess = this.assertOwner(sessionId, ownerTransport);
    if (!sess.sessionId) return;
    sess.client.cancel(sess.sessionId).catch(() => {});
    this.cancelPendingPermissions(sess);
  }

  /** ── switchModel ────────────────────────────────────────────
   *  Change the model on a live ACP session.
   */
  async switchModel(sessionId: string, model: string, ownerTransport: WebSocket): Promise<void> {
    const sess = this.assertOwner(sessionId, ownerTransport);
    if (!sess.sessionId) throw new SessionOwnerError("SESSION_NOT_FOUND", "session is not initialized");
    if (!model) throw new Error("model is required");

    console.log(`[session-manager] switching model for ${sessionId.slice(0, 20)} to ${model}`);
    await sess.client.setSessionModel(sess.sessionId, model);
    setLastModel(sess.agent || "opencode", model);
    console.log(`[session-manager] model switched for ${sessionId.slice(0, 20)} to ${model}`);
  }

  /** ── setConfig ──────────────────────────────────────────────
   *  Set a session config option on a live ACP session.
   *  Returns the ACP result for the caller to forward to the client.
   */
  async setConfig(sessionId: string, configId: string, value: string, ownerTransport: WebSocket): Promise<any> {
    const sess = this.assertOwner(sessionId, ownerTransport);
    if (!sess.sessionId) throw new SessionOwnerError("SESSION_NOT_FOUND", "session is not initialized");

    const result = await sess.client.setSessionConfigOption(
      sess.sessionId,
      configId,
      value,
    );
    invalidateModelListCache(sess.agent || undefined);
    return result;
  }

  /** ── setMode ────────────────────────────────────────────────
   *  Set the active mode on a live ACP session.
   */
  async setMode(sessionId: string, modeId: string, ownerTransport: WebSocket): Promise<void> {
    const sess = this.assertOwner(sessionId, ownerTransport);
    if (!sess.sessionId) throw new SessionOwnerError("SESSION_NOT_FOUND", "session is not initialized");
    await sess.client.setSessionMode(sess.sessionId, modeId);
  }

  /** ── tryReuseSession ───────────────────────────────────────
   *  If a session with the given ID already exists in the pool, reclaim
   *  it for the new WebSocket connection and optionally send sync replay.
   *  Returns true if reused, false if the session needs to be created fresh.
   */
  tryReuseSession(
    ws: WebSocket,
    sessionId: string,
    lastMessageId?: string,
  ): boolean {
    const existing = this.sessions.get(sessionId);
    if (!existing) return false;
    if (existing.ownerTransport && existing.ownerTransport !== ws) return false;
    if (!existing.ownerTransport && existing.orphanedAt !== null) {
      this.claimSession(existing, ws);
    } else if (existing.ownerTransport === ws) {
      existing.ws = ws;
      existing.ownerId = this.transportIdentity(ws);
    } else {
      return false;
    }
    this.updateSessionActivity(sessionId);
    console.log(
      `[session-manager] reclaimed existing session: ${sessionId.slice(0, 20)}`,
    );

    // Send sync replay if requested
    if (lastMessageId) {
      const syncResult = this.replayBuffer(sessionId, lastMessageId, ws);
      if (syncResult.entries.length > 0) {
        try {
          ws.send(
            JSON.stringify({
              type: "sync_response",
              sessionId,
              entries: syncResult.entries,
              overflow: syncResult.overflow,
            }),
          );
        } catch { /* WS gone */ }
      }
    }

    return true;
  }

  /** ── getSession ─────────────────────────────────────────────
   *  Look up a session by bridge key. Returns undefined if not found. */
  getSession(sessionId: string): SessionState | undefined {
    return this.sessions.get(sessionId);
  }

  /** ── findSessionForWs ───────────────────────────────────────
   *  Find the first session associated with a WebSocket connection. */
  findSessionForWs(ws: WebSocket): SessionState | undefined {
    for (const sess of this.sessions.values()) {
      if (sess.ownerTransport === ws) return sess;
    }
    return undefined;
  }

  /** ── getAllSessions ──────────────────────────────────────────
   *  Return a readonly view of all registered sessions. */
  getAllSessions(): ReadonlyMap<string, SessionState> {
    return this.sessions;
  }

  /** ── getActiveSessionIds ────────────────────────────────────
   *  Return session IDs currently in an active turn (turnActive=true).
   *  Used by session-watcher to override disk-based status with live state. */
  getActiveSessionIds(): Set<string> {
    const ids = new Set<string>();
    for (const [id, s] of this.sessions) {
      if (s.turnActive) ids.add(id);
    }
    return ids;
  }

  /** ── enqueueWsOp ────────────────────────────────────────────
   *  Serialize WebSocket operations so they execute one at a time
   *  per connection. Errors are caught and logged.
   */
  public enqueueWsOp(ws: import("ws").WebSocket, fn: () => Promise<void>): void {
    const prev = this.wsOpQueues.get(ws) || Promise.resolve();
    const next = prev.catch(() => {}).then(async () => {
      try {
        await fn();
      } catch (err: any) {
        console.log(`[server] queued op error: ${err.message}`);
      }
    });
    this.wsOpQueues.set(ws, next);
  }

  /** ── reclaimOrphanedSession ─────────────────────────────────
   *  Reclaim an orphaned (ws=null) session when a new WebSocket
   *  connects with a matching sessionId. Returns the session or
   *  undefined if not found or not orphaned.
   */
  public reclaimOrphanedSession(sessionId: string, newWs: import("ws").WebSocket): SessionState | undefined {
    const sess = this.sessions.get(sessionId);
    if (!sess) return undefined;
    if (sess.ownerTransport === newWs) return sess;
    if (sess.ownerTransport !== null || sess.orphanedAt === null) return undefined;
    this.claimSession(sess, newWs);
    this.updateSessionActivity(sessionId);
    console.log(
      `[session-manager] reclaimed orphaned session ${sessionId.slice(0, 20)}`,
    );
    return sess;
  }

  /** ── bufferedAfter ──────────────────────────────────────────
   *  Alias for replayBuffer — return buffered events after a
   *  given messageId for cursor sync.
   */
  public bufferedAfter(
    sessionId: string,
    lastMessageId: string,
  ): {
    entries: Array<{ messageId: string; payload: string; timestamp: number }>;
    overflow: boolean;
  } {
    return this.replayBuffer(sessionId, lastMessageId);
  }

  // ═══════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════

  /** Build the onPermissionRequest callback for AcpClientCallbacks.
   *  Extracted to avoid duplication between getOrCreate and restartSession.
   *  sessionIdRef is a thunk so the captured sessionId can be reassigned
   *  externally (let-variable pattern).
   */
  private buildPermissionRequestCallback(
    wsRef: import("ws").WebSocket | null | undefined,
    sessionIdRef: () => string,
  ): (permParams: RequestPermissionRequest) => Promise<RequestPermissionResponse> {
    return (permParams) =>
      new Promise((resolve) => {
        const requestId = randomUUID();
        const sid = sessionIdRef();
        const s = this.sessions.get(sid);
        // orphan（会话存在但无 owner）时立即取消，避免 ACP Promise 永久挂起
        if (s && !s.ownerTransport) {
          resolve({ outcome: { outcome: "cancelled" } });
          return;
        }
        if (s) {
          s.pendingPermissions.set(requestId, {
            requestId,
            sessionId: sid,
            // 该请求实际提供的 option ID 集合，响应校验用
            optionIds: permParams.options.map((o) => o.optionId),
            resolve,
          });
        }
        try {
          // orphan 时不向旧连接发权限请求（cleanupWsSessions 已取消该会话的 pending）
          const currentWs = s ? s.ownerTransport : wsRef;
          currentWs?.send(
            JSON.stringify({
              type: "permission_request",
              sessionId: sid,
              requestId,
              toolCall: permParams.toolCall,
              options: permParams.options,
            }),
          );
        } catch { /* WS gone */ }
      });
  }

  private cancelPendingPermissions(sess: SessionState): void {
    if (sess.pendingPermissions.size === 0) return;
    for (const pending of sess.pendingPermissions.values()) {
      pending.resolve({ outcome: { outcome: "cancelled" } });
    }
    sess.pendingPermissions.clear();
  }

  private finishTurn(sessionId: string, reason?: string): void {
    const sess = this.sessions.get(sessionId);
    if (!sess) return;
    sess.turnActive = false;
    delete sess.resetTimeout;
    this.cancelPendingPermissions(sess);
    this.bufferAgentEvent(sessionId, {
      type: "agent_event",
      sessionId,
      event: { sessionUpdate: "turn_ended", stopReason: reason },
    });
    this.sendToOwner(sessionId, {
      type: "turn_ended",
      sessionId,
      stopReason: reason,
    });
  }

  /** Touch lastActivity and slide the prompt inactivity timer. */
  private updateSessionActivity(sessionId: string): void {
    const sess = this.sessions.get(sessionId);
    if (!sess) return;
    sess.lastActivity = Date.now();
    if (sess.resetTimeout) {
      try {
        sess.resetTimeout();
      } catch { /* reset function threw — ignore */ }
    }
  }

  /** Buffer a COPY of the event payload for cursor-sync replay, assigning
   *  a monotonic messageId. Returns the buffered payload (with messageId)
   *  so callers can send it over WS without relying on implicit mutation. */
  public bufferAgentEvent(
    sessionId: string,
    eventPayload: object,
  ): object | undefined {
    const sess = this.sessions.get(sessionId);
    if (!sess) return undefined;

    let seq = (this.sessionSeqCounter.get(sessionId) || 0) + 1;
    this.sessionSeqCounter.set(sessionId, seq);
    const messageId = `${sessionId}:${seq}`;

    // Clone — never mutate the caller-owned object
    const buffered = { ...(eventPayload as Record<string, unknown>), messageId };
    sess.messageBuffer.push({
      messageId,
      payload: JSON.stringify(buffered),
      timestamp: Date.now(),
    });

    // Sliding window trim
    if (sess.messageBuffer.length > MAX_MESSAGE_BUFFER) {
      const excess = sess.messageBuffer.length - MAX_MESSAGE_BUFFER;
      sess.messageBuffer.splice(0, excess);
    }
    return buffered;
  }

  /** Orphan all sessions bound to a WebSocket (keep their ACP
   *  processes alive for background execution). */
  cleanupWsSessions(ws: WebSocket): void {
    const now = Date.now();
    for (const [id, sess] of this.sessions) {
      if (sess.ownerTransport !== ws) continue;
      sess.orphanedAt = now;
      sess.ownerTransport = null;
      sess.ownerId = null;
      sess.ws = null;
      this.cancelPendingPermissions(sess);
      this.updateSessionActivity(id);
      console.log(
        `[session-manager] session ${id.slice(0, 20)} orphaned (process kept alive)`,
      );
      this.ensureIdleCleanupRunning();
    }
    this.wsOpQueues.delete(ws);
    this.enforceProcessPoolLimit();
  }

  /** Stop manager-owned timers and queued transport bookkeeping. */
  public stop(): void {
    if (this.idleCleanupTimer !== null) {
      clearInterval(this.idleCleanupTimer);
      this.idleCleanupTimer = null;
    }
    this.wsOpQueues.clear();
    this.pendingCreates.clear();
    for (const sess of this.sessions.values()) {
      this.cancelPendingPermissions(sess);
    }
    this.sessions.clear();
    this.sessionSeqCounter.clear();
  }

  /** Kill an ACP session's child process and destroy its client. */
  public killSessionProcess(sess: SessionState): void {
    try {
      sess.client.destroy();
    } catch { /* ok */ }
    if (sess.process && !sess.process.killed) {
      try {
        kill(sess.process.pid!, "SIGTERM");
      } catch { /* ok */ }
    }
  }

  /** Kill all terminal sub-processes of a session. */
  private killTerminalProcesses(sess: SessionState): void {
    if (!sess.terminals) return;
    for (const [, term] of sess.terminals) {
      if (term.process && !term.process.killed) {
        try {
          kill(term.process.pid!, "SIGTERM");
        } catch { /* ok */ }
      }
    }
    sess.terminals.clear();

    // Clean terminal tool-call-id entries
    const terminalKeys: string[] = [];
    sess.toolCallIdMap.forEach((_v, k) => {
      if (k.startsWith("term-")) terminalKeys.push(k);
    });
    for (const k of terminalKeys) sess.toolCallIdMap.delete(k);

    // Trim toolCallIdMap to prevent unbounded growth
    this.trimToolCallIds(sess);
  }

  /** Enforce MAX_TOOLCALL_IDS ceiling on the session's toolCallIdMap. */
  public trimToolCallIds(sess: SessionState): void {
    if (sess.toolCallIdMap.size <= MAX_TOOLCALL_IDS) return;
    const entries = [...sess.toolCallIdMap.entries()];
    const toRemove = entries.slice(0, entries.length - MAX_TOOLCALL_IDS);
    for (const [key] of toRemove) {
      sess.toolCallIdMap.delete(key);
    }
  }

  /** Ensure the periodic idle-cleanup interval is running (lazy). */
  private ensureIdleCleanupRunning(): void {
    if (this.idleCleanupTimer !== null) return;
    this.idleCleanupTimer = setInterval(() => {
      this.evictIdle();
    }, IDLE_CLEANUP_INTERVAL_MS);
  }

  /** LRU eviction: kill oldest idle sessions until ≤ MAX_ACP_PROCESSES
   *  ACP child processes remain. Active-turn sessions are never evicted. */
  private enforceProcessPoolLimit(): void {
    const running: Array<{
      id: string;
      lastActivity: number;
      turnActive: boolean;
    }> = [];
    for (const [id, sess] of this.sessions) {
      if (sess.process && !sess.process.killed) {
        running.push({
          id,
          lastActivity: sess.lastActivity || 0,
          turnActive: sess.turnActive,
        });
      }
    }
    if (running.length <= MAX_ACP_PROCESSES) return;

    // Sort oldest-first
    running.sort((a, b) => a.lastActivity - b.lastActivity);

    const toEvict: string[] = [];
    for (const entry of running) {
      if (entry.turnActive) continue;
      toEvict.push(entry.id);
      if (running.length - toEvict.length <= MAX_ACP_PROCESSES) break;
    }

    for (const id of toEvict) {
      const sess = this.sessions.get(id);
      if (!sess) continue;
      console.log(
        `[session-manager] LRU eviction: killing idle session ${id.slice(0, 20)}`,
      );
      this.killTerminalProcesses(sess);
      this.killSessionProcess(sess);
      this.cancelPendingPermissions(sess);
      this.sessions.delete(id);
      this.sessionSeqCounter.delete(id);
    }
  }

  /** Attempt to restart a session whose ACP connection has died.
   *  Returns true on success, false if max restarts exceeded. */
  private async restartSession(sessionId: string): Promise<boolean> {
    const sess = this.sessions.get(sessionId);
    if (!sess) return false;

    sess.restartCount = (sess.restartCount || 0) + 1;
    if (sess.restartCount > 2) {
      console.log(
        `[session-manager] too many restarts for ${sessionId.slice(0, 20)}, giving up`,
      );
      try {
        sess.ws?.send(
          JSON.stringify({
            type: "error",
            sessionId,
            text: "Agent keeps crashing. Please reconnect manually.",
          }),
        );
      } catch { /* WS gone */ }
      return false;
    }

    console.log(
      `[session-manager] ACP connection dead for ${sessionId.slice(0, 20)}, restarting...`,
    );

    this.killTerminalProcesses(sess);
    try {
      sess.client?.destroy();
    } catch { /* ok */ }
    if (sess.process) {
      sess.process.removeAllListeners("exit");
      sess.process.removeAllListeners("error");
      if (!sess.process.killed) {
        try {
          kill(sess.process.pid!, "SIGTERM");
        } catch { /* ok */ }
      }
    }

    const cwd = sess.cwd || process.cwd();
    const proc = spawnAgentProcess(sess.agent, cwd);

    let suppressingReplay = false;
    const wsRef = sess.ws;

    const callbacks: AcpClientCallbacks = {
      onSessionUpdate: async (update) => {
        if (suppressingReplay) return;
        const s = this.sessions.get(sessionId);
        if (s) {
          recordToolCallIds(s, update.update);
          this.updateSessionActivity(sessionId);
        }
        const eventPayload = {
          type: "agent_event",
          sessionId,
          event: update.update,
        };
        let wsPayload: object;
        try {
          wsPayload = this.bufferAgentEvent(sessionId, eventPayload) ?? eventPayload;
        } catch { /* ok */
          wsPayload = eventPayload;
        }
        try {
          const s = this.sessions.get(sessionId);
          const currentWs = s ? s.ownerTransport : wsRef;
          if (currentWs) currentWs.send(JSON.stringify(wsPayload));
        } catch { /* WS gone */ }
      },
      onPermissionRequest: this.buildPermissionRequestCallback(wsRef, () => sessionId),
      ...createAcpCallbacks({
        getSessionId: () => sessionId,
        cwd,
        toolCallIdMap: sess.toolCallIdMap,
      }),
    };

    const client = this.clientFactory.create(proc, callbacks);

    proc.stderr?.on("data", (chunk: Buffer) => {
      console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    });
    proc.on("error", (err: Error) => {
      console.log(`[session-manager] restarted ${sess.agent} process error: ${err.message}`);
      try {
        sess.ws?.send(JSON.stringify({ type: "error", sessionId, code: "AGENT_SPAWN_FAILED", text: `Agent restart failed: ${err.message}` }));
      } catch { /* WS gone */ }
    });
    proc.on("exit", (code) => {
      console.log(
        `[session-manager] ${sessionId.slice(0, 20)} restarted process exited with code ${code}`,
      );
      if (this.sessions.has(sessionId)) {
        const s = this.sessions.get(sessionId)!;
        this.killTerminalProcesses(s);
        this.cancelPendingPermissions(s);
        this.sessions.delete(sessionId);
        this.sessionSeqCounter.delete(sessionId);
      }
    });

    let reloadSessionId: string;
    let acpSessionId: string;
    try {
      await initializeWithTimeout(client, proc);
      reloadSessionId = sess.sessionId;
      if (reloadSessionId) {
      suppressingReplay = true;
      try {
        console.log(
          `[session-manager] reloading session ${reloadSessionId.slice(0, 20)}...`,
        );
        await client.loadSession(reloadSessionId, cwd);
        acpSessionId = reloadSessionId;
      } catch {
        console.log(
          `[session-manager] loadSession failed, creating new session`,
        );
        const result = await client.createSession(cwd);
        acpSessionId = result.sessionId;
      } finally {
        suppressingReplay = false;
      }
      } else {
        const result = await client.createSession(cwd);
        acpSessionId = result.sessionId;
      }
    } catch (err: unknown) {
      try { client.destroy(); } catch { /* ok */ }
      if (!proc.killed) {
        try { kill(proc.pid!, "SIGTERM"); } catch { /* ok */ }
      }
      throw err;
    }

    sess.process = proc;
    sess.client = client;
    sess.sessionId = acpSessionId;
    this.cancelPendingPermissions(sess);
    sess.restartCount = 0;

    const lastModel = getLastModel(sess.agent);
    if (lastModel) {
      client
        .setSessionModel(acpSessionId, lastModel)
        .catch((err: Error) => {
          console.log(
            `[session-manager] restore model failed: ${err.message}`,
          );
        });
    }

    this.sessions.set(sessionId, sess);

    console.log(
      `[session-manager] ACP session restarted: ${sessionId.slice(0, 20)}`,
    );
    return true;
  }
}

// ── Global singleton ──────────────────────────────────────────────
export const sessionManager = new SessionManager();
