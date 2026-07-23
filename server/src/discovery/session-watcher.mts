import os from "os";
import path from "path";
import fs from "fs";

export interface ActiveSessionStatus {
  sessionId: string;
  agentName: string;
  cwd?: string;
  status: "running" | "waiting_input" | "idle" | "error";
  lastActivity: number;
}

/**
 * Discovers and checks local active sessions from OpenCode, Claude Code, and Codex.
 * Dual-channel fallback: scans local FS logs when ACP API doesn't report active state.
 */
export function getLocalAgentLocations(): Record<string, string[]> {
  const home = os.homedir();
  const isWin = os.platform() === "win32";
  const appData = isWin ? (process.env.APPDATA || path.join(home, "AppData", "Roaming")) : "";

  return {
    opencode: [
      path.join(home, ".opencode", "opencode.db"),
      path.join(home, ".config", "opencode", "opencode.db"),
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

export function scanLocalSessionStatuses(): ActiveSessionStatus[] {
  const results: ActiveSessionStatus[] = [];
  const home = os.homedir();

  // Scan Claude Code session directory
  const claudeDir = path.join(home, ".claude", "sessions");
  if (fs.existsSync(claudeDir)) {
    try {
      const files = fs.readdirSync(claudeDir);
      for (const f of files) {
        if (f.endsWith(".json")) {
          const fp = path.join(claudeDir, f);
          const stat = fs.statSync(fp);
          const isRunning = Date.now() - stat.mtimeMs < 15000;
          results.push({
            sessionId: f.replace(".json", ""),
            agentName: "claude-code",
            status: isRunning ? "running" : "idle",
            lastActivity: stat.mtimeMs,
          });
        }
      }
    } catch (_) {}
  }

  return results;
}
