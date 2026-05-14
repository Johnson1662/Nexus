import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import os from "node:os";

export interface McpServerConfig {
  name: string;
  type: "stdio" | "http" | "sse";
  command?: string;
  args?: string[];
  url?: string;
  headers?: { name: string; value: string }[];
  env?: { name: string; value: string }[];
}

function parseMcpServers(servers: Record<string, any>): McpServerConfig[] {
  return Object.entries(servers)
    .filter(([, s]) => s.enabled !== false)
    .map(([name, s]) => {
      if (s.transport === "http" || s.transport === "sse") {
        return {
          name,
          type: s.transport,
          url: s.url,
          headers: Object.entries(s.headers || {}).map(([k, v]) => ({
            name: k,
            value: String(v),
          })),
        };
      }
      return {
        name,
        type: "stdio",
        command: s.command,
        args: s.args || [],
        env: Object.entries(s.env || {}).map(([k, v]) => ({
          name: k,
          value: String(v),
        })),
      };
    });
}

const APP_DATA = process.env.APPDATA || path.join(os.homedir(), "AppData", "Roaming");
const HOME = os.homedir();

const AGENT_CONFIG_PATHS: Record<string, string[]> = {
  opencode: [".commandcode/mcp.json"],
  "claude-code": [
    path.join(APP_DATA, "Claude", "claude_desktop_config.json"),
    path.join(APP_DATA, "Claude Code", "config.json"),
    path.join(HOME, ".claude", "claude_desktop_config.json"),
  ],
  cline: [
    path.join(APP_DATA, "Code - OSS", "User", "globalStorage", "saoudrizwan.claude-dev", "settings", "cline_mcp_settings.json"),
    path.join(APP_DATA, "Cursor", "User", "globalStorage", "saoudrizwan.claude-dev", "settings", "cline_mcp_settings.json"),
    path.join(APP_DATA, "Windsurf", "User", "globalStorage", "saoudrizwan.claude-dev", "settings", "cline_mcp_settings.json"),
  ],
  cursor: [".cursor/mcp.json"],
  goose: [
    path.join(HOME, ".config", "goose", "config.yaml"),
    path.join(HOME, ".config", "goose", "config.json"),
  ],
};

export function loadMcpConfigForAgent(agentName: string, cwd?: string): McpServerConfig[] {
  const configPaths = AGENT_CONFIG_PATHS[agentName] || [];

  for (const configPath of configPaths) {
    try {
      const absPath = path.isAbsolute(configPath)
        ? configPath
        : path.join(cwd || process.cwd(), configPath);
      if (existsSync(absPath)) {
        const raw = JSON.parse(readFileSync(absPath, "utf-8"));
        const servers = raw.mcpServers || {};
        return parseMcpServers(servers);
      }
    } catch {}
  }

  try {
    const fallbackPath = path.join(cwd || process.cwd(), ".commandcode", "mcp.json");
    if (existsSync(fallbackPath)) {
      const raw = JSON.parse(readFileSync(fallbackPath, "utf-8"));
      return parseMcpServers(raw.mcpServers || {});
    }
  } catch {}

  return [];
}
