import path from "node:path";
import { homedir } from "node:os";
import { existsSync, readdirSync, readlinkSync, statSync, realpathSync, readFileSync } from "node:fs";
import { execSync } from "node:child_process";
import { getHerdrConfig } from "../registry/registry.mjs";
import { HerdrCliClient, HerdrCliError, resolveHerdrBinary } from "./herdr-cli.mjs";

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

// ── Herdr Adapter API ─────────────────────────────────

/** True when a Herdr CLI failure carries the given Herdr error code. */
export function isHerdrCode(err: unknown, code: string): boolean {
  return err instanceof HerdrCliError && err.herdrCode === code;
}

export interface HerdrProbeResult {
  available: boolean;
  binary?: string;
  reason?: string;
  checkedAt: number;
}

let lastProbeResult: HerdrProbeResult | null = null;
const PROBE_CACHE_TTL_MS = 3000;

export class HerdrAdapter {
  /** Cheap pre-flight for messaging only; never gates a business call. */
  static isAvailable(): boolean {
    return resolveHerdrBinary() !== null;
  }

  static async probe(force = false): Promise<HerdrProbeResult> {
  const now = Date.now();
    if (!force && lastProbeResult && now - lastProbeResult.checkedAt < PROBE_CACHE_TTL_MS) {
  return lastProbeResult;
    }
    const binary = resolveHerdrBinary();
    if (!binary) {
      lastProbeResult = { available: false, reason: "Herdr executable not found", checkedAt: now };
  return lastProbeResult;
    }
    try {
      await HerdrCliClient.runJson(["agent", "list"]);
      lastProbeResult = { available: true, binary, checkedAt: now };
          } catch (err) {
    lastProbeResult = {
      available: false,
        binary,
        reason: err instanceof Error ? err.message : String(err),
      checkedAt: now,
    };
    }
    return lastProbeResult;
  }

  /** Integration install state keyed by Herdr target (integrations are optional). */
  static async getIntegrationStatus(): Promise<Record<string, boolean>> {
    const result: Record<string, boolean> = {};
    try {
      const stdout = await HerdrCliClient.run(["integration", "status"], { timeoutMs: 8000 });
      for (const line of stdout.split("\n")) {
        const match = /^(\S+):\s+(current|not installed|outdated)\s*\((.*)\)\s*$/.exec(line.trim());
        if (match) result[match[1]] = match[2] === "current";
      }
    } catch (err) {
      console.log(`[herdr-adapter] getIntegrationStatus error: ${String(err)}`);
    }
    return result;
  }

  static async listWorkspaces(): Promise<HerdrWorkspaceInfo[]> {
    try {
      const res = await HerdrCliClient.runJson<{ workspaces?: HerdrWorkspaceInfo[] }>(["workspace", "list"]);
      return res?.workspaces ?? [];
    } catch (err) {
      console.log(`[herdr-adapter] listWorkspaces error: ${String(err)}`);
      return [];
    }
  }

  static async createWorkspace(label?: string, cwd?: string): Promise<string | null> {
    const args = ["workspace", "create", "--no-focus"];
    if (label) args.push("--label", label);
    if (cwd) args.push("--cwd", cwd);
    const res = await HerdrCliClient.runJson<{ workspace?: { workspace_id: string } }>(args, {
      timeoutMs: 15000,
    });
    return res?.workspace?.workspace_id ?? null;
  }

  static async focusWorkspace(workspaceId: string): Promise<void> {
    await HerdrCliClient.run(["workspace", "focus", workspaceId]);
  }

  static async splitPane(options: {
    workspace_id?: string;
    target_pane_id?: string;
    direction?: "right" | "down";
    cwd?: string;
  }): Promise<string | null> {
    const target = options.target_pane_id ?? options.workspace_id;
    const args = ["pane", "split"];
    if (target) args.push("--pane", target);
    args.push("--direction", options.direction ?? "right");
    if (options.cwd) args.push("--cwd", options.cwd);
    const res = await HerdrCliClient.runJson<{ pane?: { pane_id: string } }>(args, {
      timeoutMs: 15000,
    });
    return res?.pane?.pane_id ?? null;
  }

  static async createTab(options: {
    workspace_id: string;
    label?: string;
    cwd?: string;
  }): Promise<string | null> {
    const args = ["tab", "create", "--workspace", options.workspace_id, "--no-focus"];
    if (options.label) args.push("--label", options.label);
    if (options.cwd) args.push("--cwd", options.cwd);
    const res = await HerdrCliClient.runJson<{ root_pane?: { pane_id: string } }>(args, {
      timeoutMs: 15000,
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
    // A freshly split pane needs a moment before its shell reaches an
    // interactive prompt; retry only on agent_pane_busy, fail fast otherwise.
    // Herdr agent startup defaults to a 30s timeout; stay above it so a slow
    // start is not misreported as failure (which would leak the new pane).
    const tries = options.retries ?? 12;
    const delayMs = options.retryDelayMs ?? 800;
    const args = [
      "agent", "start", options.name,
      "--kind", options.kind,
      "--pane", options.pane_id,
      "--timeout", "30000",
    ];
    if (options.args && options.args.length > 0) args.push("--", ...options.args);
    let lastErr: unknown = null;
    for (let attempt = 0; attempt <= tries; attempt++) {
      try {
        await HerdrCliClient.runJson(args, { timeoutMs: 35000 });
        return true;
      } catch (err) {
        lastErr = err;
        if (!isHerdrCode(err, "agent_pane_busy") || attempt === tries) throw err;
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }
    throw lastErr;
  }

  static async closePane(paneId: string): Promise<void> {
    await HerdrCliClient.run(["pane", "close", paneId]);
  }

  static async focusAgent(target: string): Promise<void> {
    await HerdrCliClient.run(["agent", "focus", target.replace(/^herdr:/, "")]);
  }

  static async listAgents(): Promise<HerdrAgentInfo[]> {
    try {
      const res = await HerdrCliClient.runJson<{ agents?: HerdrAgentInfo[] }>(["agent", "list"]);
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
    return HerdrCliClient.run([
      "agent", "read", target,
      "--lines", String(lines),
      "--format", format,
    ], { timeoutMs: 8000 });
  }

  /** Strict status read; throws HerdrCliError on transport failure. */
  static async getAgent(target: string): Promise<HerdrAgentInfo> {
    const res = await HerdrCliClient.runJson<{ agent?: HerdrAgentInfo }>([
      "agent", "get", target.replace(/^herdr:/, ""),
    ]);
    if (!res?.agent) {
      throw new HerdrCliError("HERDR_BAD_JSON", `Herdr returned no agent for ${target}`, "agent_not_found");
    }
    return res.agent;
  }

  /**
   * Block until the agent reaches one of `until`, returning the observed
   * status. Throws on timeout or transport failure; the caller decides whether
   * that is a cancellation failure.
   */
  static async waitForStatus(
    target: string,
    until: Array<HerdrAgentInfo["agent_status"]> = ["idle", "done"],
    timeoutMs = 8000,
  ): Promise<HerdrAgentInfo["agent_status"]> {
    const args = ["agent", "wait", target.replace(/^herdr:/, "")];
    for (const status of until) args.push("--until", status);
    args.push("--timeout", String(timeoutMs));
    const res = await HerdrCliClient.runJson<{ agent?: HerdrAgentInfo }>(args, {
      timeoutMs: timeoutMs + 3000,
    });
    const status = res?.agent?.agent_status ?? "unknown";
    // `--until` guarantees a match or an error; a status outside the requested
    // set means we cannot claim the turn ended.
    if (!until.includes(status)) {
      throw new HerdrCliError(
        "HERDR_EXIT",
        `Herdr reported "${status}" while waiting for ${until.join("/")}`,
        "unexpected_status",
      );
    }
    return status;
  }

  static async sendPrompt(target: string, text: string): Promise<void> {
    const paneId = target.replace(/^herdr:/, "");
    let lastError: unknown = null;
    for (let attempt = 0; attempt < 10; attempt += 1) {
      try {
        const agent = (await this.listAgents()).find((item) => item.pane_id === paneId);
        if (!agent || agent.agent_status === "unknown") {
          throw new HerdrCliError(
            "HERDR_EXIT",
            `Herdr CLI error [agent_not_ready]: agent for pane ${paneId} is not ready`,
            "agent_not_ready",
          );
        }
        await HerdrCliClient.run(["agent", "prompt", paneId, text]);
        return;
      } catch (err) {
        lastError = err;
        if (!isHerdrCode(err, "agent_not_ready") || attempt === 9) throw err;
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
    }
    throw lastError;
  }

  static async sendKeys(target: string, keys: string[]): Promise<void> {
    await HerdrCliClient.run(["agent", "send-keys", target.replace(/^herdr:/, ""), ...keys]);
  }

  /** Type literal text into a pane (not interpreted as key names). */
  static async sendText(paneId: string, text: string): Promise<void> {
    await HerdrCliClient.run(["pane", "send-text", paneId.replace(/^herdr:/, ""), text]);
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
    const supportsStructuredHistory = getHerdrConfig(match.agent)?.structuredHistory === true;

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
