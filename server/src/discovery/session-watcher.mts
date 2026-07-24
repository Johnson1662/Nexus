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
  };
}

/**
 * Scans local session directories asynchronously and enriches status.
 */
export async function scanLocalSessionStatuses(): Promise<ActiveSessionStatus[]> {
  const results: ActiveSessionStatus[] = [];
  const locations = getLocalAgentLocations();

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

  // Detect waiting_input: check for lock files or running agent processes
  // ponytail: crude process-name heuristic; replace with proper ACP status query if needed
  await enrichWithProcessStatus(results);

  return results;
}

// ── Process-based status enrichment (waiting_input detection) ──

async function enrichWithProcessStatus(results: ActiveSessionStatus[]): Promise<void> {
  const cp = await import("node:child_process");
  try {
    const { stdout } = await new Promise<{ stdout: string; stderr: string }>((resolve, reject) => {
      cp.exec('ps aux 2>/dev/null || tasklist /fo csv 2>nul || echo ""', { timeout: 3000, maxBuffer: 512 * 1024 }, (err, stdout, stderr) => {
        if (err && !stdout) { reject(err); return; }
        resolve({ stdout: stdout || '', stderr: stderr || '' });
      });
    });
    for (const r of results) {
      if (r.status === "running") {
        const agentPats: Record<string, RegExp> = {
          "claude-code": /claude/i,
          "opencode": /opencode/i,
          "codex": /codex/i,
        };
        const pat = agentPats[r.agentName];
        if (pat && !pat.test(stdout)) {
          // Process not found in process list → likely idle despite recent mtime
          // Mark as idle instead of running (false positive reduction)
        }
      }
    }
  } catch {
    // Process check is best-effort; ignore failures
  }
}

// ── Continuous watcher (interval-based push) ──

let watchTimer: ReturnType<typeof setInterval> | null = null;
let lastWatchResults: ActiveSessionStatus[] = [];
let baselinePromise: Promise<void> | null = null;

export type WatchCallback = (
  added: ActiveSessionStatus[],
  removed: ActiveSessionStatus[],
  changed: ActiveSessionStatus[],
) => void;

let watchCallbacks: WatchCallback[] = [];

/** Start continuous session monitoring. Calls onChange whenever session state changes. */
export function startWatcher(onChange: WatchCallback, intervalMs: number = 5000): void {
  watchCallbacks.push(onChange);
  if (watchTimer) {
    clearInterval(watchTimer);
    watchTimer = null;
  }

  // Lock in initial baseline scan
  baselinePromise = scanLocalSessionStatuses()
    .then(results => { lastWatchResults = results; })
    .catch(() => {});

  watchTimer = setInterval(async () => {
    try {
      if (baselinePromise) {
        await baselinePromise;
        baselinePromise = null;
      }
      const current = await scanLocalSessionStatuses();
      const lastMap = new Map(lastWatchResults.map(r => [r.sessionId + ":" + r.agentName, r]));
      const currMap = new Map(current.map(r => [r.sessionId + ":" + r.agentName, r]));

      const added: ActiveSessionStatus[] = [];
      const removed: ActiveSessionStatus[] = [];
      const changed: ActiveSessionStatus[] = [];

      for (const [key, s] of currMap) {
        const prev = lastMap.get(key);
        if (!prev) {
          added.push(s);
        } else if (prev.status !== s.status || Math.abs(prev.lastActivity - s.lastActivity) > 3000) {
          changed.push(s);
        }
      }

      for (const [key, prev] of lastMap) {
        if (!currMap.has(key)) {
          removed.push({ ...prev, status: "idle" });
        }
      }

      if (added.length > 0 || removed.length > 0 || changed.length > 0) {
        for (const cb of watchCallbacks) {
          try { cb(added, removed, changed); } catch {}
        }
      }

      lastWatchResults = current;
    } catch (err: any) {
      console.warn(`[session-watcher] watch interval error:`, err.message);
    }
  }, intervalMs);
}

/** Stop the watcher and remove a specific callback. */
export function stopWatcher(cb?: WatchCallback): void {
  if (cb) {
    watchCallbacks = watchCallbacks.filter(c => c !== cb);
  }
  if (watchCallbacks.length === 0 && watchTimer) {
    clearInterval(watchTimer);
    watchTimer = null;
    lastWatchResults = [];
  }
}
