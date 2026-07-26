import os from "os";
import path from "path";
import fs from "fs/promises";
import { existsSync } from "fs";

export interface ActiveSessionStatus {
  sessionId: string;
  agentName: string;
  cwd?: string;
  status: "running" | "waiting_input" | "idle" | "error";
  lastActivity: number;
}

/**
 * Discovers and checks local active session locations for OpenCode, Claude Code, and Codex.
 */
export function getLocalAgentLocations(): Record<string, string[]> {
  const home = os.homedir();
  const isWin = os.platform() === "win32";
  const appData = isWin ? (process.env.APPDATA || path.join(home, "AppData", "Roaming")) : "";

  return {
    opencode: [
      path.join(home, ".opencode", "opencode.db"),
      path.join(home, ".config", "opencode", "opencode.db"),
      path.join(home, ".local", "share", "opencode", "opencode.db"),
      path.join(home, "Library", "Application Support", "opencode", "opencode.db"),
      ...(isWin && appData ? [path.join(appData, "opencode", "opencode.db")] : []),
    ],
    claude: [
      path.join(home, ".claude", "sessions"),
      path.join(home, ".config", "claude", "sessions"),
    ],
    codex: [
      path.join(home, ".codex", "history.jsonl"),
      path.join(home, ".codex", "sessions"),
    ],
    omp: [
      path.join(home, ".omp", "agent", "agent.db"),
      path.join(home, ".omp", "agent", "sessions"),
      path.join(home, ".omp", "sessions"),
      path.join(home, ".omp", "history"),
    ],
  };
}

/**
 * Scans local session directories asynchronously.
 */
export async function scanLocalSessionStatuses(): Promise<ActiveSessionStatus[]> {
  const results: ActiveSessionStatus[] = [];
  const locations = getLocalAgentLocations();

  // Scan OMP session directories & agent.db WAL for status
  for (const ompTarget of (locations.omp || [])) {
    if (existsSync(ompTarget)) {
      try {
        const walFile = `${ompTarget}-wal`;
        const targetFile = existsSync(walFile) ? walFile : ompTarget;
        const stat = await fs.stat(targetFile);
        if (stat.isFile()) {
          const isRunning = Date.now() - stat.mtimeMs < 15000;
          results.push({
            sessionId: "omp-active",
            agentName: "omp",
            status: isRunning ? "running" : "idle",
            lastActivity: stat.mtimeMs,
          });
        } else if (stat.isDirectory()) {
          const files = await fs.readdir(ompTarget);
          for (const f of files) {
            if (f.endsWith(".json") || f.endsWith(".jsonl")) {
              const fp = path.join(ompTarget, f);
              const fstat = await fs.stat(fp);
              const isRunning = Date.now() - fstat.mtimeMs < 15000;
              results.push({
                sessionId: f.replace(/\.(json|jsonl)$/, ""),
                agentName: "omp",
                status: isRunning ? "running" : "idle",
                lastActivity: fstat.mtimeMs,
              });
            }
          }
        }
      } catch (err: any) {
        console.warn(`[session-watcher] Error scanning omp target ${ompTarget}:`, err.message);
      }
    }
  }

  // Scan Claude Code session directory
  for (const claudeDir of locations.claude) {
    if (existsSync(claudeDir)) {
      try {
        const files = await fs.readdir(claudeDir);
        for (const f of files) {
          if (f.endsWith(".json")) {
            const fp = path.join(claudeDir, f);
            const stat = await fs.stat(fp);
            const isRunning = Date.now() - stat.mtimeMs < 15000;
            results.push({
              sessionId: f.replace(".json", ""),
              agentName: "claude-code",
              status: isRunning ? "running" : "idle",
              lastActivity: stat.mtimeMs,
            });
          }
        }
      } catch (err: any) {
        console.warn(`[session-watcher] Error scanning claude dir ${claudeDir}:`, err.message);
      }
    }
  }

  // Scan OpenCode session directories or DB file for status
  for (const baseDb of locations.opencode) {
    if (existsSync(baseDb)) {
      try {
        const walFile = `${baseDb}-wal`;
        const targetFile = existsSync(walFile) ? walFile : baseDb;
        const stat = await fs.stat(targetFile);
        const isRunning = Date.now() - stat.mtimeMs < 15000;
        results.push({
          sessionId: "opencode-active",
          agentName: "opencode",
          status: isRunning ? "running" : "idle",
          lastActivity: stat.mtimeMs,
        });
      } catch (err: any) {
        console.warn(`[session-watcher] Error checking opencode db ${baseDb}:`, err.message);
      }
    }
    const sessionsDir = path.join(path.dirname(baseDb), "sessions");
    if (existsSync(sessionsDir)) {
      try {
        const entries = await fs.readdir(sessionsDir, { withFileTypes: true });
        for (const e of entries) {
          if (e.isDirectory() || e.isFile()) {
            const fp = path.join(sessionsDir, e.name);
            const stat = await fs.stat(fp);
            const isRunning = Date.now() - stat.mtimeMs < 15000;
            results.push({
              sessionId: path.basename(e.name, path.extname(e.name)),
              agentName: "opencode",
              status: isRunning ? "running" : "idle",
              lastActivity: stat.mtimeMs,
            });
          }
        }
      } catch (err: any) {
        console.warn(`[session-watcher] Error scanning opencode sessions ${sessionsDir}:`, err.message);
      }
    }
  }

  // Scan Codex session directories
  for (const codexEntry of locations.codex) {
    const codexBase = path.dirname(codexEntry);
    const sessionsDir = path.join(codexBase, "sessions");
    if (existsSync(sessionsDir)) {
      try {
        const entries = await fs.readdir(sessionsDir, { withFileTypes: true });
        for (const e of entries) {
          if (e.isDirectory() || e.isFile()) {
            const fp = path.join(sessionsDir, e.name);
            const stat = await fs.stat(fp);
            const isRunning = Date.now() - stat.mtimeMs < 15000;
            results.push({
              sessionId: path.basename(e.name, path.extname(e.name)),
              agentName: "codex",
              status: isRunning ? "running" : "idle",
              lastActivity: stat.mtimeMs,
            });
          }
        }
      } catch (err: any) {
        console.warn(`[session-watcher] Error scanning codex dir ${sessionsDir}:`, err.message);
      }
    }
  }

  return results;
}

// ── Pure diff function (deterministic, testable) ──

export interface SessionDiff {
  added: ActiveSessionStatus[];
  removed: ActiveSessionStatus[];
  changed: ActiveSessionStatus[];
}

/**
 * Computes the diff between two snapshots of session statuses.
 * Pure function — no I/O, no side effects.
 *
 * - New entries → `added`
 * - Removed entries → `removed` (with status forced to "idle")
 * - Entries whose status changed or lastActivity drifted by >3s → `changed`
 */
export function computeSessionDiff(
  prev: ActiveSessionStatus[],
  curr: ActiveSessionStatus[],
): SessionDiff {
  const prevMap = new Map(prev.map(r => [r.sessionId + ":" + r.agentName, r]));
  const currMap = new Map(curr.map(r => [r.sessionId + ":" + r.agentName, r]));

  const added: ActiveSessionStatus[] = [];
  const removed: ActiveSessionStatus[] = [];
  const changed: ActiveSessionStatus[] = [];

  for (const [key, s] of currMap) {
    const prevEntry = prevMap.get(key);
    if (!prevEntry) {
      added.push(s);
    } else if (
      prevEntry.status !== s.status ||
      Math.abs(prevEntry.lastActivity - s.lastActivity) > 3000
    ) {
      changed.push(s);
    }
  }

  for (const [key, prevEntry] of prevMap) {
    if (!currMap.has(key)) {
      removed.push({ ...prevEntry, status: "idle" });
    }
  }

  return { added, removed, changed };
}

/**
 * Merge disk-scanned session statuses with live SessionManager state.
 * For any session whose turnActive=true in memory, override disk status
 * to "running" regardless of file mtime.
 *
 * Pure function — independently testable.
 */
export function mergeSessionStatus(
  diskResults: ActiveSessionStatus[],
  activeIds: Set<string>,
): ActiveSessionStatus[] {
  if (activeIds.size === 0) return diskResults;
  return diskResults.map(s => {
    if (activeIds.has(s.sessionId)) {
      return { ...s, status: "running" as const };
    }
    return s;
  });
}

// ── SessionStatusWatcher class (deep module) ──

export class SessionStatusWatcher {
  private timer: ReturnType<typeof setInterval> | null = null;
  private lastResults: ActiveSessionStatus[] = [];
  private baselinePromise: Promise<void> | null = null;
  private listeners: Array<(diff: SessionDiff) => void> = [];
  private intervalMs: number;

  constructor(intervalMs: number = 5000) {
    this.intervalMs = intervalMs;
  }

  /**
   * Performs a single scan of local session statuses.
   * Useful for testing or one-shot checks.
   */
  async scanOnce(): Promise<ActiveSessionStatus[]> {
    return scanLocalSessionStatuses();
  }

  /**
   * Register a listener that fires whenever the watcher detects a diff.
   * The listener receives `{ added, removed, changed }`.
   */
  onStatusUpdate(listener: (diff: SessionDiff) => void): void {
    this.listeners.push(listener);
  }

  /**
   * Start continuous monitoring. Runs an initial baseline scan,
   * then polls every `intervalMs` milliseconds.
   * No-op if already started.
   */
  start(): void {
    if (this.timer) return;

    // Lock in initial baseline scan
    this.baselinePromise = this.scanOnce()
      .then(results => { this.lastResults = results; })
      .catch(() => {});

    this.timer = setInterval(async () => {
      try {
        if (this.baselinePromise) {
          await this.baselinePromise;
          this.baselinePromise = null;
        }
        const current = await this.scanOnce();
        const diff = computeSessionDiff(this.lastResults, current);

        if (diff.added.length > 0 || diff.removed.length > 0 || diff.changed.length > 0) {
          for (const listener of this.listeners) {
            try { listener(diff); } catch { /* swallow listener errors */ }
          }
        }

        this.lastResults = current;
      } catch (err: any) {
        console.warn(`[session-watcher] watch interval error:`, err.message);
      }
    }, this.intervalMs);
  }

  /**
   * Stop continuous monitoring and reset internal state.
   */
  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    this.lastResults = [];
    this.baselinePromise = null;
    this.listeners = [];
  }
}
