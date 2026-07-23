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

  // Scan OpenCode database / session files
  for (const dbPath of locations.opencode) {
    if (existsSync(dbPath)) {
      try {
        const stat = await fs.stat(dbPath);
        const isRunning = Date.now() - stat.mtimeMs < 15000;
        results.push({
          sessionId: "opencode_active",
          agentName: "opencode",
          status: isRunning ? "running" : "idle",
          lastActivity: stat.mtimeMs,
        });
        break;
      } catch (err: any) {
        console.warn(`[session-watcher] Error checking opencode db ${dbPath}:`, err.message);
      }
    }
  }

  return results;
}
