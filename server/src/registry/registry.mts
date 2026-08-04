import { readFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// ── Types ─────────────────────────────────────────────────────────────

export interface RegistryAgent {
  id: string;
  name: string;
  description: string;
  version: string;
  repository?: string;
  icon?: string;
  distribution: {
    direct?: {
      cmd: string;
      args: string[];
      env?: Record<string, string>;
    };
    npx?: {
      package: string;
      args: string[];
      env?: Record<string, string>;
    };
    binary?: Record<string, {
      archive: string;
      cmd: string;
      args: string[];
      env?: Record<string, string>;
    }>;
  };
}

export interface AgentRegistry {
  version: number;
  agents: RegistryAgent[];
}

// ── State ─────────────────────────────────────────────────────────────

const CURRENT_DIR = path.dirname(fileURLToPath(import.meta.url));
const BUILTIN_PATH = path.join(CURRENT_DIR, "agents.json");

let registry: AgentRegistry | null = null;

function validCommand(cmd: unknown): cmd is string {
  return typeof cmd === "string" && cmd.trim().length > 0 && !/[\u0000\r\n]/.test(cmd);
}

function validArgs(args: unknown): args is string[] {
  return Array.isArray(args) && args.every(arg => typeof arg === "string" && !/[\u0000\r\n]/.test(arg));
}

function validLaunch(value: unknown): value is { cmd: string; args: string[]; env?: Record<string, string> } {
  if (!value || typeof value !== "object") return false;
  const launch = value as { cmd?: unknown; args?: unknown; env?: unknown };
  return validCommand(launch.cmd) && validArgs(launch.args);
}

function validRegistryAgent(value: unknown): value is RegistryAgent {
  if (!value || typeof value !== "object") return false;
  const agent = value as Partial<RegistryAgent>;
  return typeof agent.id === "string" && agent.id.length > 0
    && typeof agent.name === "string"
    && !!agent.distribution && typeof agent.distribution === "object";
}

// ── Public API ────────────────────────────────────────────────────────

export function loadRegistry(refresh: boolean = false): AgentRegistry {
  if (registry && !refresh) return registry;
  try {
    const raw = readFileSync(BUILTIN_PATH, "utf-8");
    const parsed = JSON.parse(raw) as Partial<AgentRegistry>;
    registry = {
      version: typeof parsed.version === "number" ? parsed.version : 1,
      agents: Array.isArray(parsed.agents) ? parsed.agents.filter(validRegistryAgent) : [],
    };
    console.log(`[registry] loaded ${registry.agents.length} agents from built-in registry`);
  } catch (err) {
    console.log(`[registry] failed to load built-in registry: ${err}`);
    registry = { version: 1, agents: [] };
  }
  return registry;
}

export function getRegistryAgent(agentId: string): RegistryAgent | undefined {
  if (!registry) loadRegistry();
  return registry!.agents.find(a => a.id === agentId);
}

export function listRegistryAgents(): RegistryAgent[] {
  if (!registry) loadRegistry();
  return registry!.agents;
}

/**
 * Resolve the launch command for an agent from its distribution config.
 * Priority: direct → npx → binary (first matching platform).
 * Returns null if no launch method is available.
 */
export function resolveAgentCommand(agentId: string): { cmd: string; args: string[]; env?: Record<string, string> } | null {
  const agent = getRegistryAgent(agentId);
  if (!agent) return null;

  // direct launch (simplest)
  if (validLaunch(agent.distribution.direct)) {
    return { cmd: agent.distribution.direct.cmd, args: [...agent.distribution.direct.args], env: agent.distribution.direct.env };
  }

  // npx launch
  if (agent.distribution.npx
      && typeof agent.distribution.npx.package === "string"
      && agent.distribution.npx.package.length > 0
      && validArgs(agent.distribution.npx.args)) {
    return {
      cmd: "npx",
      args: ["--yes", agent.distribution.npx.package, ...agent.distribution.npx.args],
      env: agent.distribution.npx.env,
    };
  }

  // Binary launch must match this host; never pick an arbitrary platform.
  if (agent.distribution.binary) {
    const target = agent.distribution.binary[process.platform]
      || agent.distribution.binary[process.platform === "win32" ? "windows" : process.platform];
    if (target && validCommand(target.cmd) && validArgs(target.args)) {
      return { cmd: target.cmd, args: [...target.args], env: target.env };
    }
  }

  return null;
}

export function getAgentDisplayName(agentId: string): string {
  const agent = getRegistryAgent(agentId);
  return agent?.name ?? agentId;
}

/**
 * Attempt to fetch a remote registry. Falls back to built-in on failure.
 */
export async function fetchRemoteRegistry(url?: string): Promise<AgentRegistry> {
  const registryUrl = url || process.env.ANYWHERE_REGISTRY_URL || "https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json";
  try {
    const response = await fetch(registryUrl);
    if (!response.ok) {
      console.log(`[registry] remote fetch returned ${response.status}, using built-in`);
      return loadRegistry();
    }
    const remote = await response.json() as Partial<AgentRegistry>;
    if (remote && Array.isArray(remote.agents)) {
      // Merge only structurally valid entries; launchers remain argv-based.
      const byId = new Map<string, RegistryAgent>();
      for (const a of loadRegistry().agents) byId.set(a.id, a);
      for (const a of remote.agents) {
        if (validRegistryAgent(a)) byId.set(a.id, a);
      }
      const merged: AgentRegistry = { version: typeof remote.version === "number" ? remote.version : 1, agents: Array.from(byId.values()) };
      registry = merged;
      console.log(`[registry] merged ${remote.agents.length} remote agents into registry`);
      return merged;
    }
  } catch (err) {
    console.log(`[registry] remote fetch failed: ${err}`);
  }
  return loadRegistry();
}