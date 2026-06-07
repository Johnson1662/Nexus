import { execSync, spawn, type SpawnOptions } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import os from "node:os";

interface AgentEntry {
  binary: string;
  title: string;
  args: string[];
}

const ACP_AGENTS: AgentEntry[] = [
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
for (const entry of ACP_AGENTS) {
  AGENT_ARGS_MAP.set(entry.binary, entry.args);
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

function findInPath(binaryName: string): string | null {
  const pathDirs = (process.env.PATH || "").split(path.delimiter);
  // Also check local node_modules/.bin for npm-installed packages
  const localBin = path.join(process.cwd(), "node_modules", ".bin");

  if (pathDirs.indexOf(localBin) === -1) {
    pathDirs.push(localBin);
  }
  // Prefer .exe (native) over .cmd/.bat (need shell) over .ps1
  // Iterate extensions first so we find .exe anywhere on PATH before .cmd
  const extensions = [".exe", ".cmd", ".bat", ".ps1", ""];
  for (const ext of extensions) {
    for (const dir of pathDirs) {
      if (!dir) continue;
      const fullPath = path.join(dir.trim(), binaryName + ext);
      try {
        if (existsSync(fullPath)) return fullPath;
      } catch {}
    }
  }
  return null;
}

// Some agents fail on --version but respond to --help
const SKIP_VERSION_CHECK = new Set(["codex-acp"]);

function getAgentVersion(binaryPath: string, binaryName: string): string | null {
  const commands = SKIP_VERSION_CHECK.has(binaryName) ? ["--help"] : ["--version", "--help"];
  for (const cmd of commands) {
    try {
      const result = execSync(`"${binaryPath}" ${cmd}`, {
        encoding: "utf8",
        timeout: 3000,
      });
      return result.trim().split("\n")[0];
    } catch {
      // try next command
    }
  }
  return null;
}


export function discoverAgents(): AgentInfo[] {
  const discovered: AgentInfo[] = [];
  for (const entry of ACP_AGENTS) {
    const binaryPath = findInPath(entry.binary);
    if (binaryPath) {
      const version = getAgentVersion(binaryPath, entry.binary);
      discovered.push({
        name: entry.binary,
        title: entry.title,
        version: version || "unknown",
        source: "path",
        binaryPath,
        installed: true,
      });
    }
  }
  console.log(
    `[server] discovered ${discovered.length} ACP agents: ${discovered.map((a) => a.name).join(", ")}`
  );
  return discovered;
}
