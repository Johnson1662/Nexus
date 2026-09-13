import kill from "tree-kill";
import { spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, realpathSync, statSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { WebSocket } from "ws";
import { AcpClient, type AcpClientCallbacks } from "./acp/client.mjs";
import type { AuthMethod, RequestPermissionRequest, RequestPermissionResponse } from "@agentclientprotocol/sdk";
import type { SessionState } from "./acp/types.mjs";
import { resolveAgentRuntime } from "./agents-store.mjs";
import { resolveWorkspacePath, resolveExplicitCwd } from "./path-utils.mjs";
import { createAcpCallbacks } from "./acp-callbacks.mjs";
import { getLastModel, setLastModel } from "./prefs.mjs";
import { recordToolCallIds } from "./tool-call-map.mjs";
import { extractModelList, setCachedModelList, invalidateModelListCache } from "./model-list.mjs";
import {
  boundAgentEventPayload,
  countToolContentBytes,
  MAX_TOOL_CONTENT_BYTES,
  MAX_REPLAY_BYTES_PER_SESSION,
} from "./payload-budget.mjs";


// ── Constants ────────────────────────────────────────────────────
const MAX_TOOLCALL_IDS = 500;
const IDLE_TIMEOUT_MS = 15 * 60 * 1_000;
const MAX_ACP_PROCESSES = 5;
const IDLE_CLEANUP_INTERVAL_MS = 30_000;
const MAX_MESSAGE_BUFFER = 500;
const PROMPT_TIMEOUT = 300_000; // 5 minutes sliding inactivity
export const CANCEL_WATCHDOG_TIMEOUT_MS = 10_000;
const AGENT_INITIALIZE_TIMEOUT_MS = 30_000;
export const ACP_SESSION_OPERATION_TIMEOUT_MS = 30_000;
export const ACP_CLOSE_SESSION_TIMEOUT_MS = 5_000;

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

export class SessionOperationError extends Error {
  constructor(public readonly code: "SESSION_OPERATION_IN_PROGRESS" | "SESSION_CLOSING", message: string) {
    super(message);
    this.name = "SessionOperationError";
  }
}

export class AcpDeadlineError extends Error {
  constructor(public readonly operation: string) {
    super(`${operation} timeout`);
    this.name = "AcpDeadlineError";
  }
}

export class AuthenticationRequiredError extends Error {
  constructor(
    public readonly sessionId: string,
    public readonly authMethods: AuthMethod[],
    cause: unknown,
  ) {
    super(cause instanceof Error ? cause.message : String(cause));
    this.name = "AuthenticationRequiredError";
  }
}

function resolveAgentLaunch(agent: string): { cmd: string; args: string[]; env: Record<string, string> } {
  const runtime = resolveAgentRuntime(agent);
  if (!runtime || !runtime.cmd || !Array.isArray(runtime.args) || runtime.args.some((arg: unknown) => typeof arg !== "string")) {
    throw new Error(`invalid or unavailable agent: ${agent}`);
  }
  if (!runtime.installed) {
    throw new Error(`agent is not installed: ${agent}`);
  }
  if (!runtime.native.enabled) {
    throw new Error(`agent does not provide native ACP transport: ${agent}`);
  }
  if (!runtime.executablePath) {
    throw new Error(`agent command not found in PATH: ${runtime.cmd}`);
  }
  return { cmd: runtime.cmd, args: [...runtime.args], env: { ...runtime.env } };
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

function isAuthenticationFailure(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /auth(?:entication|orization)?|log[ -]?in|credential|unauthorized|forbidden|\b40[13]\b/i.test(message);
}

export function withAcpDeadline<T>(
  label: string,
  operation: () => Promise<T>,
  timeoutMs = ACP_SESSION_OPERATION_TIMEOUT_MS,
): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      reject(new AcpDeadlineError(label));
    }, timeoutMs);

    void Promise.resolve()
      .then(operation)
      .then(
        (value) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve(value);
        },
        (error: unknown) => {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          reject(error);
        },
      );
  });
}

async function initializeWithTimeout(
  client: AcpClient,
  proc: ChildProcess,
  timeoutMs = AGENT_INITIALIZE_TIMEOUT_MS,
): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let rejectProcessError: (error: Error) => void = () => {};
  const onProcessError = (error: Error) => rejectProcessError(error);
  const processError = new Promise<never>((_resolve, reject) => {
    rejectProcessError = (error: Error) => reject(new Error(`agent process failed: ${error.message}`));
    proc.once("error", onProcessError);
  });
  const timeout = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new Error("agent initialize timeout")), timeoutMs);
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

export interface SessionManagerOptions {
  acpSessionOperationTimeoutMs?: number;
  closeSessionTimeoutMs?: number;
  cancelWatchdogMs?: number;
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
  private pendingOperations = new Map<import("ws").WebSocket, Promise<SessionState>>();
  private pendingCreates = new Map<import("ws").WebSocket, Promise<SessionState>>();
  private transportIds = new WeakMap<object, string>();
  private idleCleanupTimer: ReturnType<typeof setInterval> | null = null;
  private clientFactory: AcpClientFactory;
  private acpSessionOperationTimeoutMs: number;
  private closeSessionTimeoutMs: number;
  private cancelWatchdogMs: number;

  constructor(factory?: AcpClientFactory, options: SessionManagerOptions = {}) {
    this.clientFactory = factory ?? {
      create: (proc, callbacks) => new AcpClient(proc, callbacks),
    };
    this.acpSessionOperationTimeoutMs = options.acpSessionOperationTimeoutMs ?? ACP_SESSION_OPERATION_TIMEOUT_MS;
    this.closeSessionTimeoutMs = options.closeSessionTimeoutMs ?? ACP_CLOSE_SESSION_TIMEOUT_MS;
    this.cancelWatchdogMs = options.cancelWatchdogMs ?? CANCEL_WATCHDOG_TIMEOUT_MS;
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
    sess.subscribers ??= new Set();
    sess.subscribers.add(transport);
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
    sess.subscribers ??= new Set();
    if (!sess.subscribers.has(transport)) {
      if (sess.ownerTransport === transport) {
        sess.subscribers.add(transport);
      } else if (sess.ownerTransport === null || sess.subscribers.size === 0) {
        this.claimSession(sess, transport);
      } else {
        sess.subscribers.add(transport);
        sess.orphanedAt = null;
      }
    }
    return sess;
  }

  // ═══════════════════════════════════════════════════════════════
  // PUBLIC API — 9 methods
  // ═══════════════════════════════════════════════════════════════

  /** 该 WS 是否已有进行中的 Session 创建任务（用于 start 准入，拒绝重复 Start）。 */
  public hasPendingCreate(ws: import("ws").WebSocket): boolean {
    return this.pendingOperations.has(ws);
  }

  /** Reserve explicit close synchronously so a following input cannot race it. */
  public beginClose(sessionId: string, ownerTransport: WebSocket): void {
    const sess = this.assertOwner(sessionId, ownerTransport);
    if (sess.closing) {
      throw new SessionOperationError("SESSION_CLOSING", "session is already closing");
    }
    sess.closing = true;
    sess.closingOwnerId = sess.ownerId ?? this.transportIdentity(ownerTransport);
  }

  /** ── getOrCreate ─────────────────────────────────────────────
   *  Return the session matching `params.sessionId` if already alive,
   *  or spawn a new ACP agent process, initialise the ACP protocol,
   *  and register the session in the pool.
   */
  async getOrCreate(ws: WebSocket, params: CreateSessionParams): Promise<SessionState> {
    const mode = params.mode ?? "create";
    const inFlight = this.pendingOperations.get(ws);
    if (inFlight) {
      // Duplicate starts may share the same create promise, but a load/resume
      // must never receive the session created by a different operation.
      if (mode === "create" && this.pendingCreates.get(ws) === inFlight) return inFlight;
      throw new SessionOperationError(
        "SESSION_OPERATION_IN_PROGRESS",
        "another session operation is already in progress",
      );
    }
    const pending = this.getOrCreateInternal(ws, params);
    this.pendingOperations.set(ws, pending);
    if (mode === "create") this.pendingCreates.set(ws, pending);
    try {
      return await pending;
    } finally {
      if (this.pendingOperations.get(ws) === pending) this.pendingOperations.delete(ws);
      if (this.pendingCreates.get(ws) === pending) this.pendingCreates.delete(ws);
    }
  }

  private async getOrCreateInternal(ws: WebSocket, params: CreateSessionParams): Promise<SessionState> {
    const {
      agent = "omp",
      cwd,
      model,
      mode = "create",
    } = params;
    const targetSessionId = params.sessionId;

    // Re-use existing session if still live
    if (targetSessionId) {
      const existing = this.sessions.get(targetSessionId);
      if (existing) {
        if (existing.closing) {
          throw new SessionOperationError("SESSION_CLOSING", "session is closing");
        }
        existing.subscribers ??= new Set();
        existing.subscribers.add(ws);
        existing.ownerTransport = ws;
        existing.ws = ws;
        existing.ownerId = this.transportIdentity(ws);
        existing.orphanedAt = null;
        this.updateSessionActivity(targetSessionId);
        if (mode === "load" || mode === "resume") {
          if (existing.client?.connected && existing.sessionId) {
            return existing;
          }
          if (!existing.loadInFlight) {
            existing.loadInFlight = withAcpDeadline(
              `${mode}Session`,
              () => mode === "load"
                ? existing.client.loadSession(targetSessionId, existing.cwd).then(() => undefined)
                : existing.client.resumeSession(targetSessionId, existing.cwd).then(() => undefined),
              this.acpSessionOperationTimeoutMs,
            ).finally(() => {
              existing.loadInFlight = undefined;
            });
          }
          try {
            await existing.loadInFlight;
          } catch (error) {
            // A timed-out ACP load/resume leaves the connection state
            // ambiguous. Dispose it so the next request cannot inherit a
            // permanently locked loadInFlight/client/process.
            this.disposeSession(targetSessionId, existing);
            throw error;
          }
        }
        return existing;
      }
    }

    // Orphan any previous sessions belonging to this WS
    this.cleanupWsSessions(ws);

    const launch = resolveAgentLaunch(agent);
    const ANYWHERE_DIR = join(homedir(), ".nexus");
    mkdirSync(ANYWHERE_DIR, { recursive: true });
    // Missing cwd → the default data dir; explicit-but-invalid cwd → error.
    const resolvedCwd = resolveExplicitCwd(cwd, ANYWHERE_DIR);
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
      subscribers: new Set([wsRef]),
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
      toolContentBytesByCallId: new Map(),
      turnActive: false,
      turnGeneration: 0,
      clientGeneration: 0,
      lastActivity: Date.now(),
      orphanedAt: null,
      messageBuffer: [],
      replayBytes: 0,
    };

    // ── Build ACP callbacks ────────────────────────────────────
    const callbackGeneration = sess.clientGeneration + 1;
    sess.clientGeneration = callbackGeneration;
    const isCurrentClient = () => {
      const current = this.sessions.get(sessionId);
      return !sessionId || (current === sess && current.clientGeneration === callbackGeneration);
    };
    const callbacks: AcpClientCallbacks = {
      onSessionUpdate: async (update) => {
        const s = this.sessions.get(sessionId);
        if (sessionId && (!s || s !== sess || s.clientGeneration !== callbackGeneration)) return;
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
          wsPayload = this.bufferAgentEvent(sessionId, eventPayload) ??
            boundAgentEventPayload(eventPayload).value;
        } catch { /* buffer full — discard */
          wsPayload = boundAgentEventPayload(eventPayload).value;
        }
        try {
          const s = this.sessions.get(sessionId);
          if (s) {
            this.broadcastToSubscribers(sessionId, wsPayload);
          } else if (wsRef) {
            wsRef.send(JSON.stringify(wsPayload));
          }
        } catch { /* WS disconnected — event buffered */ }
      },
      onPermissionRequest: this.buildPermissionRequestCallback(wsRef, () => sessionId, isCurrentClient),
      onExtMethod: this.buildExtMethodCallback(() => sessionId, this.buildPermissionRequestCallback(wsRef, () => sessionId, isCurrentClient)),
      ...createAcpCallbacks({
        getSessionId: () => sessionId,
        cwd: resolvedCwd,
        toolCallIdMap: sess.toolCallIdMap,
        isCurrentClient,
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
    const isCurrentProcess = () => {
      const current = this.sessions.get(sessionId);
      return Boolean(sessionId) && current === sess && sess.clientGeneration === callbackGeneration;
    };
    proc.stderr.on("data", (chunk: Buffer) => {
      console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    });
    proc.on("error", (err: Error) => {
      if (!isCurrentProcess()) return;
      console.log(`[session-manager] ${agent} process error: ${err.message}`);
      this.sendToOwner(sessionId, {
        type: "error",
        sessionId,
        code: "AGENT_SPAWN_FAILED",
        text: `Agent process failed: ${err.message}`,
      });
      const current = this.sessions.get(sessionId);
      if (current === sess) {
        this.killTerminalProcesses(sess);
        this.cancelPendingPermissions(sess);
        this.sessions.delete(sessionId);
        this.sessionSeqCounter.delete(sessionId);
      }
    });
    proc.on("exit", (code) => {
      if (!isCurrentProcess()) return;
      console.log(`[server] ${sessionId} process exited with code ${code}`);
      const s = this.sessions.get(sessionId);
      if (s === sess) {
        this.killTerminalProcesses(s);
        this.cancelPendingPermissions(s);
        this.sessions.delete(sessionId);
        this.sessionSeqCounter.delete(sessionId);
      }
    });

    // ── ACP initialisation ─────────────────────────────────────
    try {
      await initializeWithTimeout(client, proc);
      if (mode === "load" && targetSessionId) {
        sess.loadInFlight = withAcpDeadline(
          "loadSession",
          () => client.loadSession(targetSessionId, resolvedCwd).then(() => undefined),
          this.acpSessionOperationTimeoutMs,
        ).finally(() => {
          sess.loadInFlight = undefined;
        });
        await sess.loadInFlight;
        sessionId = targetSessionId;
      } else if (mode === "resume" && targetSessionId) {
        sess.loadInFlight = withAcpDeadline(
          "resumeSession",
          () => client.resumeSession(targetSessionId, resolvedCwd).then(() => undefined),
          this.acpSessionOperationTimeoutMs,
        ).finally(() => {
          sess.loadInFlight = undefined;
        });
        await sess.loadInFlight;
        sessionId = targetSessionId;
      } else {
        const result = await withAcpDeadline(
          "createSession",
          () => client.createSession(resolvedCwd),
          this.acpSessionOperationTimeoutMs,
        );
        sessionId = result.sessionId;
      }
    } catch (err: unknown) {
      if (!targetSessionId && client.authMethods.length > 0 && isAuthenticationFailure(err)) {
        sessionId = `auth:${randomUUID()}`;
        sess.sessionId = sessionId;
        this.sessions.set(sessionId, sess);
        this.ensureIdleCleanupRunning();
        throw new AuthenticationRequiredError(sessionId, client.authMethods, err);
      }
      // Tear down on any init/create/load/resume failure. In particular,
      // targetSessionId may already be present in the map as a partial
      // session, so leaving it there would poison the next request.
      this.disposeSession(targetSessionId || sessionId, sess);
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

  /** Broadcast a payload to all active subscribers of the session. */
  public broadcastToSubscribers(sessionId: string, payload: object, excludeWs?: WebSocket): void {
    const sess = this.sessions.get(sessionId);
    if (!sess) return;
    const json = JSON.stringify(payload);
    if (sess.subscribers && sess.subscribers.size > 0) {
      for (const sub of sess.subscribers) {
        if (excludeWs && sub === excludeWs) continue;
        try {
          sub.send(json);
        } catch { /* WS gone */ }
      }
    } else if (sess.ownerTransport && sess.ownerTransport !== excludeWs) {
      try {
        sess.ownerTransport.send(json);
      } catch { /* WS gone */ }
    }
  }

  private sendToOwner(sessionId: string, payload: object): void {
    this.broadcastToSubscribers(sessionId, payload);
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
    if (sess.closing) {
      throw new SessionOperationError("SESSION_CLOSING", "session is closing");
    }
    if (sess.turnActive) {
      throw new Error("session turn already active");
    }
    if (!sess.sessionId) {
      throw new SessionOwnerError("SESSION_NOT_FOUND", "session is not initialized");
    }
    // Claim the turn BEFORE any await so concurrent inputs are
    // rejected atomically (input_ack is only sent on success).
    sess.turnActive = true;
    sess.turnGeneration = (sess.turnGeneration ?? 0) + 1;
    const turnGeneration = sess.turnGeneration;
    this.updateSessionActivity(sessionId);

    // Broadcast user prompt to other subscribers so their chat timeline stays in sync
    this.broadcastToSubscribers(
      sessionId,
      {
        type: "agent_event",
        sessionId,
        event: {
          sessionUpdate: "user_message_chunk",
          content: { type: "text", text },
        },
      },
      ownerTransport,
    );

    return {
      run: () => this.runPromptTurn(sessionId, text, turnGeneration).catch((err: unknown) => {
        const msg = err instanceof Error ? err.message : String(err);
        console.log(`[session-manager] prompt turn error: ${msg}`);
        if (this.invalidateClientAfterForcedTurnEnd(sessionId, turnGeneration) &&
          this.finishTurn(sessionId, "error", turnGeneration)) {
          this.sendToOwner(sessionId, {
            type: "error",
            sessionId,
            text: `Agent error: ${msg}`,
          });
        }
      }),
    };
  }

  /** ── runPromptTurn ──────────────────────────────────────────
   *  Async prompt body: auto-restart of a dead ACP connection,
   *  keep-alive heartbeat, sliding inactivity timeout and stderr
   *  model-error monitoring. All turn_ended / error frames go
   *  through sendToOwner — never a captured transport.
   */
  private async runPromptTurn(sessionId: string, text: string, turnGeneration: number): Promise<void> {
    // Auto-recover dead ACP connection by restarting the session
    let liveSess = this.sessions.get(sessionId);
    if (!liveSess || !liveSess.sessionId || !liveSess.client || !this.isCurrentTurn(liveSess, turnGeneration)) {
      return;
    }
    if (!liveSess.client.connected || liveSess.requiresClientRestart) {
      let ok = await this.restartSession(sessionId);
      // A cancel watchdog may have invalidated a recovery candidate after it
      // released the old turn. A newer turn must wait for that stale recovery
      // to settle, then get one fresh candidate rather than surfacing a
      // recovery error to the user.
      liveSess = this.sessions.get(sessionId);
      if (!ok && liveSess && liveSess.requiresClientRestart &&
        this.isCurrentTurn(liveSess, turnGeneration)) {
        ok = await this.restartSession(sessionId);
      }
      if (!ok) {
        liveSess = this.sessions.get(sessionId);
        if (liveSess?.cancelRequestedGeneration === turnGeneration) {
          delete liveSess.cancelRequestedGeneration;
          this.finishTurn(sessionId, "cancelled", turnGeneration);
          return;
        }
        if (liveSess && this.invalidateClientAfterForcedTurnEnd(sessionId, turnGeneration) &&
          this.finishTurn(sessionId, "error", turnGeneration)) {
          this.sendToOwner(sessionId, {
            type: "error",
            sessionId,
            text: `Failed to restart session: ${sessionId}`,
          });
        }
        return;
      }
    }

    // Guard: session may have been cleaned up during restart
    liveSess = this.sessions.get(sessionId);
    if (!liveSess || !liveSess.sessionId || !liveSess.client || !this.isCurrentTurn(liveSess, turnGeneration)) {
      return;
    }
    if (liveSess.cancelRequestedGeneration === turnGeneration) {
      delete liveSess.cancelRequestedGeneration;
      liveSess.client.cancel(liveSess.sessionId).catch(() => {});
      this.finishTurn(sessionId, "cancelled", turnGeneration);
      return;
    }

    const startTime = Date.now();
    let timedOut = false;
    let errorDetected = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let stderrHandler: ((chunk: Buffer) => void) | null = null;
    let cleanedUp = false;

    // Heartbeat keep-alive during prompt
    const keepAlive = setInterval(() => {
      if (timedOut || errorDetected || !this.isCurrentTurn(liveSess, turnGeneration)) return;
      this.sendToOwner(sessionId, { type: "heartbeat", sessionId, ts: Date.now() });
    }, 3_000);

    const cleanupTurn = () => {
      if (cleanedUp) return;
      cleanedUp = true;
      clearInterval(keepAlive);
      clearTimeout(timer);
      if (stderrHandler && liveSess.process?.stderr) {
        try {
          liveSess.process.stderr.removeListener("data", stderrHandler);
        } catch { /* ok */ }
      }
      if (liveSess.turnCleanup === cleanupTurn) delete liveSess.turnCleanup;
    };
    liveSess.turnCleanup = cleanupTurn;

    // ── stderr model-error monitoring ─────────────────────────
    if (liveSess.process?.stderr) {
      stderrHandler = (chunk: Buffer) => {
        if (errorDetected || timedOut) return;
        const stderrText = chunk.toString();
        for (const pattern of MODEL_ERROR_PATTERNS) {
          if (!pattern.test(stderrText)) continue;
          errorDetected = true;
          cleanupTurn();
          console.log(
            `[session-manager] model error detected: ${stderrText.slice(0, 200)}`,
          );
          liveSess.client.cancel(liveSess.sessionId!).catch(() => {});
          if (this.invalidateClientAfterForcedTurnEnd(sessionId, turnGeneration) &&
            this.finishTurn(sessionId, "error", turnGeneration)) {
            this.sendToOwner(sessionId, {
              type: "error",
              sessionId,
              text: `Model error: ${stderrText.slice(0, 300).trim()}`,
            });
          }
          break;
        }
      };
      liveSess.process.stderr.on("data", stderrHandler);
    }

    // ── Sliding inactivity timeout (5 min) ────────────────────
    const resetInactivityTimer = () => {
      if (timedOut || errorDetected || !this.isCurrentTurn(liveSess, turnGeneration)) return;
      clearTimeout(timer);
      timer = setTimeout(() => {
        if (errorDetected) return;
        timedOut = true;
        cleanupTurn();
        console.log(
          `[session-manager] prompt INACTIVITY TIMEOUT (5min) after ${Date.now() - startTime}ms for ${sessionId}`,
        );
        liveSess.client.cancel(liveSess.sessionId!).catch(() => {});
        if (this.invalidateClientAfterForcedTurnEnd(sessionId, turnGeneration) &&
          this.finishTurn(sessionId, "timeout", turnGeneration)) {
          this.sendToOwner(sessionId, {
            type: "error",
            sessionId,
            text: "[Timeout] 连续 5 分钟未收到任何输出或工具回调。",
          });
        }
      }, PROMPT_TIMEOUT);
    };

    liveSess.resetTimeout = resetInactivityTimer;
    resetInactivityTimer();

    // ── Issue ACP prompt ──────────────────────────────────────
    try {
      const result = await liveSess.client.prompt(liveSess.sessionId, text);

      if (timedOut || errorDetected || !this.isCurrentTurn(liveSess, turnGeneration)) {
        cleanupTurn();
        return;
      }

      cleanupTurn();
      console.log(
        `[session-manager] turn ended after ${Math.floor((Date.now() - startTime) / 1_000)}s: ${result?.stopReason}`,
      );
      this.finishTurn(sessionId, result?.stopReason, turnGeneration);
    } catch (err: unknown) {
      if (timedOut || errorDetected || !this.isCurrentTurn(liveSess, turnGeneration)) {
        cleanupTurn();
        return;
      }

      cleanupTurn();
      const msg = err instanceof Error ? err.message : String(err);
      console.log(
        `[session-manager] prompt error after ${Math.floor((Date.now() - startTime) / 1_000)}s: ${msg}`,
      );
      if (this.invalidateClientAfterForcedTurnEnd(sessionId, turnGeneration) &&
        this.finishTurn(sessionId, "error", turnGeneration)) {
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
      payloadBytes: number;
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
    const current = this.sessions.get(sessionId);
    if (!current) {
      throw new SessionOwnerError("SESSION_NOT_FOUND", "session not found");
    }
    const ownerId = this.transportIdentity(ownerTransport);
    const sess = current.closing && current.closingOwnerId === ownerId
      ? current
      : this.assertOwner(sessionId, ownerTransport);
    sess.closing = true;
    sess.closingOwnerId ??= sess.ownerId ?? ownerId;
    // Invalidate all ACP callbacks before awaiting closeSession. A recovery
    // already in flight must not commit a replacement after explicit close.
    sess.clientGeneration += 1;
    sess.turnCleanup?.();
    delete sess.turnCleanup;
    if (sess.cancelWatchdog) {
      clearTimeout(sess.cancelWatchdog);
      delete sess.cancelWatchdog;
    }
    this.cancelPendingPermissions(sess);
    const client = sess.client;

    try {
      await withAcpDeadline(
        "closeSession",
        () => client.closeSession(sess.sessionId),
        this.closeSessionTimeoutMs,
      );
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.log(`[session-manager] closeSession error: ${msg}`);
    }

    this.killSessionProcess(sess);
    this.killTerminalProcesses(sess);
    if (this.sessions.get(sessionId) === sess) {
      this.sessions.delete(sessionId);
      this.sessionSeqCounter.delete(sessionId);
    }

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
    if (!sess.turnActive) return;
    const turnGeneration = sess.turnGeneration;
    if (sess.restartInFlight) {
      sess.cancelRequestedGeneration = turnGeneration;
    }
    if (sess.cancelWatchdog) clearTimeout(sess.cancelWatchdog);
    sess.cancelWatchdog = setTimeout(() => {
      const current = this.sessions.get(sessionId);
      if (!current || !current.turnActive || current.turnGeneration !== turnGeneration) return;
      console.log(`[session-manager] cancel watchdog releasing turn for ${sessionId.slice(0, 20)}`);
      // Invalidate callbacks from the hung ACP prompt immediately. The next
      // prompt will restart this client before sending new input.
      if (this.invalidateClientAfterForcedTurnEnd(sessionId, turnGeneration)) {
        this.finishTurn(sessionId, "cancelled", turnGeneration);
      }
    }, this.cancelWatchdogMs);
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
    setLastModel(sess.agent || "omp", model);
    console.log(`[session-manager] model switched for ${sessionId.slice(0, 20)} to ${model}`);
  }

  /** ── setConfig ──────────────────────────────────────────────
   *  Set a session config option on a live ACP session.
   *  Returns the ACP result for the caller to forward to the client.
   */
  async setConfig(sessionId: string, configId: string, value: string | boolean, ownerTransport: WebSocket): Promise<any> {
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

  async authenticatePending(sessionId: string, methodId: string, ownerTransport: WebSocket): Promise<SessionState> {
    const sess = this.assertOwner(sessionId, ownerTransport);
    if (!sessionId.startsWith("auth:")) {
      await sess.client.authenticate(methodId);
      return sess;
    }

    await sess.client.authenticate(methodId);
    const result = await withAcpDeadline(
      "createSessionAfterAuth",
      () => sess.client.createSession(sess.cwd),
      this.acpSessionOperationTimeoutMs,
    );
    this.sessions.delete(sessionId);
    sess.sessionId = result.sessionId;
    this.sessions.set(sess.sessionId, sess);
    this.updateSessionActivity(sess.sessionId);
    return sess;
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
          const entries = syncResult.entries.flatMap((entry) => {
            try {
              const parsed = JSON.parse(entry.payload);
              if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return [];
              return [{
                messageId: entry.messageId,
                payload: {
                  ...parsed,
                  sessionId: parsed.sessionId || sessionId,
                  messageId: entry.messageId,
                },
                timestamp: entry.timestamp,
              }];
            } catch {
              return [];
            }
          });
          ws.send(
            JSON.stringify({
              type: "sync_response",
              sessionId,
              entries,
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
   *  Serialize WebSocket operations so they execute one at a time per
   *  connection.
   *
   *  A user-triggered operation must always produce a reply: a handler that
   *  throws without answering leaves the client waiting forever (a permanent
   *  spinner on history pagination, for instance). The failure is therefore
   *  reported to the requesting socket instead of only being logged.
   */
  public enqueueWsOp(ws: import("ws").WebSocket, fn: () => Promise<void>): void {
    const prev = this.wsOpQueues.get(ws) || Promise.resolve();
    const next = prev.catch(() => {}).then(async () => {
      try {
        await fn();
      } catch (err: any) {
        console.log(`[server] queued op error: ${err.message}`);
        try {
          ws.send(JSON.stringify({
            type: "error",
            code: err?.code ?? "OP_FAILED",
            text: err?.message ?? String(err),
          }));
        } catch { /* socket already gone */ }
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
    entries: Array<{ messageId: string; payload: string; payloadBytes: number; timestamp: number }>;
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
    isCurrentClient?: () => boolean,
  ): (permParams: RequestPermissionRequest) => Promise<RequestPermissionResponse> {
    return (permParams) =>
      new Promise((resolve) => {
        if (isCurrentClient && !isCurrentClient()) {
          resolve({ outcome: { outcome: "cancelled" } });
          return;
        }
        const requestId = randomUUID();
        const sid = sessionIdRef();
        const s = this.sessions.get(sid);
        // orphan（会话存在且没有任何订阅者）时立即取消，避免 ACP Promise 永久挂起
        if (s && !s.ownerTransport && (!s.subscribers || s.subscribers.size === 0)) {
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
          if (isCurrentClient && !isCurrentClient()) {
            s?.pendingPermissions.delete(requestId);
            resolve({ outcome: { outcome: "cancelled" } });
            return;
          }
          const permMsg = {
            type: "permission_request",
            sessionId: sid,
            requestId,
            toolCall: permParams.toolCall,
            options: permParams.options,
          };
          if (s) {
            this.broadcastToSubscribers(sid, permMsg);
          } else if (wsRef) {
            wsRef.send(JSON.stringify(permMsg));
          }
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

  /** Dispatch ACP extension requests (Cursor and future Agent extensions). */
  private buildExtMethodCallback(
    getSessionId: () => string,
    permCallback: (req: any) => Promise<any>,
  ) {
    return async (method: string, params: Record<string, unknown>) => {
      console.log(`[session-manager] handling extMethod: ${method}`);
      if (method === "cursor/ask_question") {
        const permReq = {
          sessionId: getSessionId(),
          toolCall: {
            toolCallId: `cursor_ask_${Date.now()}`,
            toolName: "ask",
            rawInput: JSON.stringify(params),
          },
          options: Array.isArray(params.options) ? params.options : [],
        };
        // The ACP permission card is the UI surface; its result is translated
        // into the answer payload Cursor expects back for the extension request.
        const outcome = (await permCallback(permReq)) as {
          outcome?: { outcome?: string; optionId?: string };
        };
        const decision = outcome?.outcome;
        if (decision?.outcome === "selected" && decision.optionId) {
          return { outcome: "answered", answer: { optionId: decision.optionId } };
        }
        return { outcome: "cancelled" };
      }
      if (method === "cursor/create_plan") {
        const sid = getSessionId();
        this.broadcastToSubscribers(sid, {
          type: "agent_event",
          sessionId: sid,
          event: {
            sessionUpdate: "plan",
            planEntries: Array.isArray(params.entries) ? params.entries : [],
          },
        });
        return { ok: true, accepted: true };
      }
      return {};
    };
  }

  private isCurrentTurn(sess: SessionState, turnGeneration: number): boolean {
    return sess.turnActive && sess.turnGeneration === turnGeneration;
  }

  /** Invalidate the ACP client before forcibly ending a live turn. */
  private invalidateClientAfterForcedTurnEnd(sessionId: string, turnGeneration: number): boolean {
    const sess = this.sessions.get(sessionId);
    if (!sess || !this.isCurrentTurn(sess, turnGeneration)) return false;
    sess.clientGeneration += 1;
    sess.requiresClientRestart = true;
    return true;
  }

  private finishTurn(sessionId: string, reason?: string, turnGeneration?: number): boolean {
    const sess = this.sessions.get(sessionId);
    if (!sess) return false;
    if (turnGeneration !== undefined && sess.turnGeneration !== turnGeneration) return false;
    sess.turnCleanup?.();
    delete sess.turnCleanup;
    if (sess.cancelWatchdog) {
      clearTimeout(sess.cancelWatchdog);
      delete sess.cancelWatchdog;
    }
    sess.turnActive = false;
    if (sess.cancelRequestedGeneration === sess.turnGeneration) {
      delete sess.cancelRequestedGeneration;
    }
    sess.turnGeneration = (sess.turnGeneration ?? 0) + 1;
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
    return true;
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

    // Clone and enforce both per-field and per-entry UTF-8 budgets before the
    // entry is retained. A single oversized event must not bypass the total
    // replay cap merely because the buffer keeps one newest entry.
    const inputPayload: Record<string, unknown> = {
      ...(eventPayload as Record<string, unknown>),
      messageId,
    };
    const event = inputPayload.event;
    const toolCallId =
      event && typeof event === "object" && !Array.isArray(event) &&
      typeof (event as Record<string, unknown>).toolCallId === "string"
        ? (event as Record<string, unknown>).toolCallId as string
        : undefined;
    // Keep compatibility with lightweight test/integration session fixtures
    // created before cumulative tool accounting was added.
    const toolContentBytesByCallId = sess.toolContentBytesByCallId ??
      (sess.toolContentBytesByCallId = new Map());
    const usedToolBytes = toolCallId
      ? toolContentBytesByCallId.get(toolCallId) ?? 0
      : 0;
    const bounded = boundAgentEventPayload(
      inputPayload,
      toolCallId
        ? { toolContentByteLimit: Math.max(0, MAX_TOOL_CONTENT_BYTES - usedToolBytes) }
        : {},
    );
    if (toolCallId) {
      const retainedToolBytes = countToolContentBytes(bounded.value);
      toolContentBytesByCallId.set(
        toolCallId,
        Math.min(MAX_TOOL_CONTENT_BYTES, usedToolBytes + retainedToolBytes),
      );
      this.trimToolContentBytes(sess);
    }
    const buffered = bounded.value;
    const { payload: serializedPayload, payloadBytes } = bounded;
    sess.messageBuffer.push({
      messageId,
      payload: serializedPayload,
      payloadBytes,
      timestamp: Date.now(),
    });
    sess.replayBytes = (sess.replayBytes ?? 0) + payloadBytes;

    // Sliding window trim
    while (sess.messageBuffer.length > MAX_MESSAGE_BUFFER) {
      const dropped = sess.messageBuffer.shift();
      if (!dropped) break;
      sess.replayBytes -= dropped.payloadBytes;
    }
    while (sess.replayBytes > MAX_REPLAY_BYTES_PER_SESSION && sess.messageBuffer.length > 1) {
      const dropped = sess.messageBuffer.shift()!;
      sess.replayBytes -= dropped.payloadBytes;
    }
    return buffered;
  }

  /** Orphan all sessions bound to a WebSocket (keep their ACP
   *  processes alive for background execution). */
  cleanupWsSessions(ws: WebSocket): void {
    const now = Date.now();
    for (const [id, sess] of this.sessions) {
      sess.subscribers ??= new Set();
      sess.subscribers.delete(ws);
      if (sess.ownerTransport === ws) {
        sess.ownerTransport = sess.subscribers.values().next().value ?? null;
        sess.ws = sess.ownerTransport;
        sess.ownerId = sess.ownerTransport ? this.transportIdentity(sess.ownerTransport) : null;
      }
      if (sess.subscribers.size === 0) {
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
    this.pendingOperations.clear();
    this.pendingCreates.clear();
    for (const sess of this.sessions.values()) {
      this.cancelPendingPermissions(sess);
    }
    this.sessions.clear();
    this.sessionSeqCounter.clear();
  }

  /** Dispose a partially initialized or unusable ACP session. */
  private disposeSession(sessionId: string, sess: SessionState): void {
    this.killTerminalProcesses(sess);
    this.cancelPendingPermissions(sess);
    this.killSessionProcess(sess);
    if (sessionId && this.sessions.get(sessionId) === sess) {
      this.sessions.delete(sessionId);
      this.sessionSeqCounter.delete(sessionId);
    }
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
      if (term.flushTimer) {
        clearTimeout(term.flushTimer);
        term.flushTimer = null;
      }
      term.exitStatus ??= { exitCode: null, signal: "SIGTERM" };
      const resolveExit = term.resolveExit;
      term.resolveExit = null;
      resolveExit?.();
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

  /** Keep cumulative tool-content accounting bounded alongside tool IDs. */
  private trimToolContentBytes(sess: SessionState): void {
    if (sess.toolContentBytesByCallId.size <= MAX_TOOLCALL_IDS) return;
    const entries = [...sess.toolContentBytesByCallId.keys()];
    for (const key of entries.slice(0, entries.length - MAX_TOOLCALL_IDS)) {
      sess.toolContentBytesByCallId.delete(key);
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

    if (sess.restartInFlight) return sess.restartInFlight;
    const pending = this.restartSessionInternal(sessionId, sess);
    sess.restartInFlight = pending;
    try {
      return await pending;
    } finally {
      if (sess.restartInFlight === pending) delete sess.restartInFlight;
    }
  }

  private async restartSessionInternal(sessionId: string, sess: SessionState): Promise<boolean> {

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
    const callbackGeneration = sess.clientGeneration + 1;
    sess.clientGeneration = callbackGeneration;
    const isCurrentClient = () => {
      const current = this.sessions.get(sessionId);
      return current === sess && current.clientGeneration === callbackGeneration;
    };

    const callbacks: AcpClientCallbacks = {
      onSessionUpdate: async (update) => {
        if (suppressingReplay) return;
        const s = this.sessions.get(sessionId);
        if (!s || s !== sess || s.clientGeneration !== callbackGeneration) return;
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
          wsPayload = this.bufferAgentEvent(sessionId, eventPayload) ??
            boundAgentEventPayload(eventPayload).value;
        } catch { /* ok */
          wsPayload = boundAgentEventPayload(eventPayload).value;
        }
        try {
          const s = this.sessions.get(sessionId);
          const currentWs = s ? s.ownerTransport : wsRef;
          if (currentWs) currentWs.send(JSON.stringify(wsPayload));
        } catch { /* WS gone */ }
      },
      onPermissionRequest: this.buildPermissionRequestCallback(wsRef, () => sessionId, isCurrentClient),
      onExtMethod: this.buildExtMethodCallback(() => sessionId, this.buildPermissionRequestCallback(wsRef, () => sessionId, isCurrentClient)),
      ...createAcpCallbacks({
        getSessionId: () => sessionId,
        cwd,
        toolCallIdMap: sess.toolCallIdMap,
        isCurrentClient,
      }),
    };

    const client = this.clientFactory.create(proc, callbacks);

    proc.stderr?.on("data", (chunk: Buffer) => {
      console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    });
    proc.on("error", (err: Error) => {
      if (!isCurrentClient()) return;
      console.log(`[session-manager] restarted ${sess.agent} process error: ${err.message}`);
      this.sendToOwner(sessionId, {
        type: "error",
        sessionId,
        code: "AGENT_SPAWN_FAILED",
        text: `Agent restart failed: ${err.message}`,
      });
    });
    proc.on("exit", (code) => {
      console.log(
        `[session-manager] ${sessionId.slice(0, 20)} restarted process exited with code ${code}`,
      );
      const s = this.sessions.get(sessionId);
      if (s === sess && sess.clientGeneration === callbackGeneration) {
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
        await withAcpDeadline(
          "restart.loadSession",
          () => client.loadSession(reloadSessionId, cwd).then(() => undefined),
          this.acpSessionOperationTimeoutMs,
        );
        acpSessionId = reloadSessionId;
      } catch (error: unknown) {
        if (error instanceof AcpDeadlineError) throw error;
        console.log(
          `[session-manager] loadSession failed, creating new session`,
        );
        const result = await withAcpDeadline(
          "restart.createSession",
          () => client.createSession(cwd),
          this.acpSessionOperationTimeoutMs,
        );
        acpSessionId = result.sessionId;
        // 旧 ACP Session 加载失败，Agent 上下文已被新 Session 替换——通知客户端（不当作 error）
        const contextEvent = {
          type: "session_context_replaced",
          sessionId,
          reason: "reload_failed",
          previousAgentSessionId: reloadSessionId,
          newAgentSessionId: acpSessionId,
        };
        try {
          if (isCurrentClient()) {
            const replayed = this.bufferAgentEvent(sessionId, contextEvent) ?? contextEvent;
            const s = this.sessions.get(sessionId);
            if (s) s.ownerTransport?.send(JSON.stringify(replayed));
          }
        } catch { /* WS gone */ }
      } finally {
        suppressingReplay = false;
      }
      } else {
        const result = await withAcpDeadline(
          "restart.createSession",
          () => client.createSession(cwd),
          this.acpSessionOperationTimeoutMs,
        );
        acpSessionId = result.sessionId;
      }
    } catch (err: unknown) {
      try { client.destroy(); } catch { /* ok */ }
      if (!proc.killed) {
        try { kill(proc.pid!, "SIGTERM"); } catch { /* ok */ }
      }
      throw err;
    }

    // Cancellation, close, or a newer recovery may have invalidated this
    // candidate while ACP load/create was awaiting. Never let stale recovery
    // resurrect a closed session or clear requiresClientRestart.
    if (!isCurrentClient()) {
      try { client.destroy(); } catch { /* ok */ }
      if (!proc.killed) {
        try { kill(proc.pid!, "SIGTERM"); } catch { /* ok */ }
      }
      return false;
    }

    sess.process = proc;
    sess.client = client;
    sess.sessionId = acpSessionId;
    sess.requiresClientRestart = false;
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
