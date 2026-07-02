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

// ── Public API ────────────────────────────────────────────────────────

export function loadRegistry(refresh: boolean = false): AgentRegistry {
  if (registry && !refresh) return registry;
  try {
    const raw = readFileSync(BUILTIN_PATH, "utf-8");
    registry = JSON.parse(raw) as AgentRegistry;
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
  if (agent.distribution.direct) {
    return { ...agent.distribution.direct };
  }

  // npx launch
  if (agent.distribution.npx) {
    return {
      cmd: "npx",
      args: ["--yes", agent.distribution.npx.package, ...agent.distribution.npx.args],
      env: agent.distribution.npx.env,
    };
  }

  // binary (try to find a matching platform, otherwise just use cmd)
  if (agent.distribution.binary) {
    const platforms = Object.keys(agent.distribution.binary);
    for (const platform of platforms) {
      const target = agent.distribution.binary![platform];
      return { cmd: target.cmd, args: target.args, env: target.env };
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
    const remote = await response.json() as AgentRegistry;
    if (remote && Array.isArray(remote.agents)) {
      // Merge: keep built-in as base, override with remote entries
      const byId = new Map<string, RegistryAgent>();
      for (const a of loadRegistry().agents) byId.set(a.id, a);
      for (const a of remote.agents) byId.set(a.id, a);
      const merged: AgentRegistry = { version: remote.version || 1, agents: Array.from(byId.values()) };
      registry = merged;
      console.log(`[registry] merged ${remote.agents.length} remote agents into registry`);
      return merged;
    }
  } catch (err) {
    console.log(`[registry] remote fetch failed: ${err}`);
  }
  return loadRegistry();
}