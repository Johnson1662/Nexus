import { spawn, type SpawnOptions } from "node:child_process";
import { existsSync, readdirSync, statSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import path from "node:path";
import { homedir } from "node:os";

interface AgentEntry {
  binary: string;
  title: string;
  args: string[];
}

const ACP_AGENTS: AgentEntry[] = [
  { binary: "pi", title: "Pi", args: ["--mode", "rpc"] },
  { binary: "opencode", title: "OpenCode", args: ["acp"] },
  { binary: "claude-agent-acp", title: "Claude Agent (ACP)", args: [] },
  { binary: "gemini", title: "Gemini CLI", args: ["--acp"] },
  { binary: "cline", title: "Cline", args: ["--acp"] },
  { binary: "kimi", title: "Kimi CLI", args: ["acp"] },
  { binary: "qwen-code", title: "Qwen Code", args: ["--acp", "--experimental-skills"] },
  { binary: "mistral-vibe", title: "Mistral Vibe", args: ["acp"] },
  { binary: "goose", title: "Goose", args: ["acp"] },
  { binary: "minion-code", title: "Minion Code", args: ["acp"] },
  { binary: "openclaw", title: "OpenClaw", args: ["acp"] },
  { binary: "qoder", title: "Qoder CLI", args: ["--acp"] },
  { binary: "vtcode", title: "VT Code", args: ["acp"] },
  { binary: "crow", title: "crow-cli", args: ["acp"] },
  { binary: "codex-acp", title: "Codex CLI", args: [] },
  { binary: "code-assistant", title: "Code Assistant", args: ["acp"] },
  { binary: "stakpak", title: "Stakpak", args: ["acp"] },
  { binary: "poolside", title: "Poolside", args: ["acp"] },
  { binary: "cursor", title: "Cursor", args: ["acp"] },
  { binary: "cursor-agent", title: "Cursor", args: ["acp"] },
  { binary: "auggie", title: "Augment Code", args: ["--acp"] },
  { binary: "augment-code", title: "Augment Code", args: ["--acp"] },
  { binary: "blackbox", title: "Blackbox AI", args: ["acp"] },
  { binary: "fast-agent", title: "fast-agent", args: ["acp"] },
  { binary: "fount", title: "fount", args: ["acp"] },
  { binary: "hermes", title: "Hermes Agent", args: ["acp"] },
  { binary: "kiro", title: "Kiro CLI", args: ["acp"] },
  { binary: "kiro-cli", title: "Kiro CLI", args: ["acp"] },
  { binary: "junie", title: "Junie", args: ["--acp=true"] },
  { binary: "copilot", title: "GitHub Copilot", args: ["--acp"] },
  { binary: "docker-cagent", title: "Docker cagent", args: ["acp"] },
  { binary: "pi", title: "pi coding agent", args: ["acp"] },
  { binary: "pi-acp", title: "pi ACP", args: [] },
  { binary: "factory-droid", title: "Factory Droid", args: ["acp"] },
  { binary: "openhands", title: "OpenHands", args: ["acp"] },
  { binary: "agoragentic", title: "Agoragentic", args: ["--acp"] },
  { binary: "amp", title: "Amp", args: ["acp"] },
  { binary: "amp-acp", title: "Amp", args: [] },
  { binary: "autohand-code", title: "Autohand Code", args: [] },
  { binary: "codebuddy", title: "Codebuddy Code", args: ["--acp"] },
  { binary: "cortex-code", title: "Cortex Code", args: ["acp", "serve"] },
  { binary: "corust-agent-acp", title: "Corust Agent", args: [] },
  { binary: "deepagents", title: "DeepAgents", args: [] },
  { binary: "dimcode", title: "DimCode", args: ["acp"] },
  { binary: "dirac", title: "Dirac", args: ["--acp"] },
  { binary: "kilo", title: "Kilo", args: ["acp"] },
  { binary: "nova", title: "Nova", args: ["acp"] },
  { binary: "sigit", title: "siGit Code", args: [] },
  { binary: "sigit-code", title: "siGit Code", args: [] },
  { binary: "glm-agent", title: "GLM Agent", args: [] },
  { binary: "rayclaw", title: "RayClaw", args: ["acp"] },
  { binary: "stdio-bus", title: "stdio Bus", args: ["acp"] },
  { binary: "iflow-cli", title: "iflow-cli", args: ["acp"] },
  { binary: "lody", title: "Lody", args: ["acp"] },
  { binary: "toad", title: "Toad", args: ["acp"] },
  { binary: "pixi", title: "pixi", args: ["acp"] },
  { binary: "tidewave", title: "Tidewave", args: ["acp"] },
  { binary: "mitto", title: "Mitto", args: ["acp"] },
  { binary: "nori-cli", title: "Nori CLI", args: ["acp"] },
  { binary: "ngent", title: "Ngent", args: ["acp"] },
  { binary: "rlm-code", title: "RLM Code", args: ["acp"] },
  { binary: "happy", title: "Happy", args: ["acp"] },
  { binary: "jockey", title: "Jockey", args: ["acp"] },
  { binary: "agente", title: "Agmente", args: ["acp"] },
  { binary: "ferngeist", title: "Ferngeist", args: ["acp"] },
  { binary: "mobvibe", title: "Mobvibe", args: ["acp"] },
  { binary: "omp", title: "oh-my-pi", args: ["acp"] },
];

const AGENT_ARGS_MAP = new Map<string, string[]>();
const AGENT_TITLE_MAP = new Map<string, string>();
for (const entry of ACP_AGENTS) {
  AGENT_ARGS_MAP.set(entry.binary, entry.args);
  AGENT_TITLE_MAP.set(entry.binary, entry.title);
}

export function getAgentLaunchArgs(agentName: string): string[] {
  return AGENT_ARGS_MAP.get(agentName) ?? ["acp"];
}

export function isValidAgent(agentName: string): boolean {
  return AGENT_ARGS_MAP.has(agentName);
}

export interface AgentInfo {
  name: string;
  title: string;
  version: string;
  source: string;
  binaryPath: string;
  installed: boolean;
}

function getPathDirs(): string[] {
  const dirs = (process.env.PATH || "").split(path.delimiter).filter(Boolean);
  const localBin = path.join(process.cwd(), "node_modules", ".bin");
  if (!dirs.includes(localBin)) dirs.push(localBin);
  return dirs;
}

// ── Cache ─────────────────────────────────────────────────────────────
const CACHE_DIR = path.join(homedir(), '.anywhere');
const CACHE_FILE = path.join(CACHE_DIR, 'agents-cache.json');
let cachedAgents: AgentInfo[] | null = null;

function loadAgentCache(): AgentInfo[] | null {
  try {
    if (!existsSync(CACHE_FILE)) return null;
    const raw = readFileSync(CACHE_FILE, 'utf-8');
    return JSON.parse(raw) as AgentInfo[];
  } catch {
    return null;
  }
}

function saveAgentCache(agents: AgentInfo[]): void {
  try {
    if (!existsSync(CACHE_DIR)) {
      mkdirSync(CACHE_DIR, { recursive: true });
    }
    writeFileSync(CACHE_FILE, JSON.stringify(agents, null, 2), 'utf-8');
  } catch (err) {
    console.log(`[agents] cache write failed: ${err}`);
  }
}

/**
 * Discover ACP agents on PATH. Result is cached to disk in ~/.anywhere/agents-cache.json
 * so subsequent server starts skip the directory scan.
 * Call refreshAgentCache() to force re-scan.
 */
export function discoverAgents(): AgentInfo[] {
  if (cachedAgents) return cachedAgents;
  const fromDisk = loadAgentCache();
  if (fromDisk) {
    cachedAgents = fromDisk;
    return cachedAgents;
  }
  cachedAgents = scanPathForAgents();
  saveAgentCache(cachedAgents);
  return cachedAgents;
}

export function refreshAgentCache(): AgentInfo[] {
  cachedAgents = null;
  const fresh = scanPathForAgents();
  saveAgentCache(fresh);
  cachedAgents = fresh;
  return fresh;
}

function scanPathForAgents(): AgentInfo[] {
  const knownNames = new Set(ACP_AGENTS.map(e => e.binary));
  const found: AgentInfo[] = [];
  const seen = new Set<string>();  // track by binary name to take first PATH hit

  for (const dir of getPathDirs()) {
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      continue;  // dir doesn't exist or not accessible
    }

    for (const name of entries) {
      const fullPath = path.join(dir, name);
      let isExe = false;
      try { isExe = statSync(fullPath).isFile(); } catch { continue; }
      if (!isExe) continue;

      // Strip extension (.exe / .cmd / .bat / .ps1)
      const parsed = path.parse(name);
      const baseName = parsed.name;

      if (knownNames.has(baseName) && !seen.has(baseName)) {
        seen.add(baseName);
        const title = AGENT_TITLE_MAP.get(baseName) ?? baseName;
        found.push({
          name: baseName,
          title,
          version: "unknown",
          source: "path",
          binaryPath: fullPath,
          installed: true,
        });
      }
    }

    if (seen.size === knownNames.size) break;  // all found
  }

  console.log(
    `[server] discovered ${found.length} ACP agents: ${found.map(a => a.name).join(", ")}`
  );
  return found;
}
