import { readFileSync, existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// ── Types ─────────────────────────────────────────────────────────────

export interface AgentDetectionConfig {
  executables: string[];
}

export interface AgentNativeConfig {
  enabled: boolean;
  command?: string;
  args?: string[];
  env?: Record<string, string>;
  adapterPackage?: string;
  adapterBinary?: string;
  minNodeMajor?: number;
  requiresBaseCli?: boolean;
  structuredHistory: boolean;
  modelSelection: boolean;
  modeSelection: boolean;
  authentication: boolean;
}

export interface AgentHerdrConfig {
  enabled: boolean;
  kind?: string;
  integration?: string;
  structuredHistory: boolean;
  modelSelection: boolean;
  modeSelection: boolean;
  authentication: boolean;
}

export interface RegistryAgent {
  id: string;
  name: string;
  description: string;
  version: string;
  repository?: string;
  icon?: string;
  detection?: AgentDetectionConfig;
  native?: AgentNativeConfig;
  herdr?: AgentHerdrConfig;
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

export function validRegistryAgent(value: unknown): value is RegistryAgent {
  if (!value || typeof value !== "object") return false;
  const agent = value as Partial<RegistryAgent>;
  return typeof agent.id === "string" && agent.id.length > 0
    && typeof agent.name === "string"
    && !!agent.distribution && typeof agent.distribution === "object"
    && isValidNativeConfig(agent.native)
    && isValidHerdrConfig(agent.herdr);
}

function validBackendFeatures(value: Record<string, unknown>): boolean {
  return typeof value.structuredHistory === "boolean"
    && typeof value.modelSelection === "boolean"
    && typeof value.modeSelection === "boolean"
    && typeof value.authentication === "boolean";
}

export function isValidNativeConfig(value: unknown): value is AgentNativeConfig {
  if (!value || typeof value !== "object") return false;
  const config = value as Record<string, unknown>;
  if (typeof config.enabled !== "boolean") return false;
  if (config.enabled && !validCommand(config.command)) return false;
  if (config.args !== undefined && !validArgs(config.args)) return false;
  if (config.adapterPackage !== undefined && typeof config.adapterPackage !== "string") return false;
  if (config.adapterBinary !== undefined && typeof config.adapterBinary !== "string") return false;
  if (config.minNodeMajor !== undefined && typeof config.minNodeMajor !== "number") return false;
  if (config.requiresBaseCli !== undefined && typeof config.requiresBaseCli !== "boolean") return false;
  return validBackendFeatures(config);
}

export function isValidHerdrConfig(value: unknown): value is AgentHerdrConfig {
  if (!value || typeof value !== "object") return false;
  const config = value as Record<string, unknown>;
  if (typeof config.enabled !== "boolean") return false;
  if (config.kind !== undefined && !validCommand(config.kind)) return false;
  if (config.integration !== undefined && !validCommand(config.integration)) return false;
  return validBackendFeatures(config);
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

export function getNativeConfig(agentId: string): AgentNativeConfig | null {
  return getRegistryAgent(agentId)?.native ?? null;
}

export function getHerdrConfig(agentId: string): AgentHerdrConfig | null {
  return getRegistryAgent(agentId)?.herdr ?? null;
}

/**
 * Map a Herdr agent kind back to the canonical Nexus agent id.
 *
 * Herdr reports the kind it launched (antigravity is `agy`), so the raw value
 * must never become a Nexus identity: capability lookups, filters and display
 * all key off the canonical id. Unknown kinds are returned unchanged.
 */
export function getAgentIdForHerdrKind(kind: string): string | null {
  if (!kind) return null;
  if (!registry) loadRegistry();
  for (const agent of registry!.agents) {
    if (agent.herdr?.kind === kind) return agent.id;
  }
  return null;
}

/**
 * Resolve the launch command for an agent from its distribution config.
 * Priority: direct → npx → binary (first matching platform).
 * Returns null if no launch method is available.
 */
export function resolveDistributionCommand(agentId: string): { cmd: string; args: string[]; env?: Record<string, string> } | null {
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