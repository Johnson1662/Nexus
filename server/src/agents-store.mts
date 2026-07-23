import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import path from "node:path";
import { homedir } from "node:os";
import { getRegistryAgent, resolveAgentCommand, getAgentDisplayName } from "./registry/registry.mjs";

// ── Types ─────────────────────────────────────────────────────────────

export interface InstalledAgent {
  agentId: string;
  installedAt: number;
  source: "registry" | "custom";
  customCommand?: string;
  customArgs?: string[];
  customEnv?: Record<string, string>;
  pinned?: boolean;
}

interface InstalledAgentsFile {
  agents: InstalledAgent[];
}

// ── State ─────────────────────────────────────────────────────────────

const STORE_DIR = path.join(homedir(), ".nexus");
const STORE_FILE = path.join(STORE_DIR, "installed-agents.json");

let installed: InstalledAgent[] | null = null;

// ── Helpers ───────────────────────────────────────────────────────────

function ensureDir(): void {
  if (!existsSync(STORE_DIR)) {
    mkdirSync(STORE_DIR, { recursive: true });
  }
}

function loadFromDisk(): InstalledAgent[] {
  if (installed) return installed;
  ensureDir();
  try {
    if (!existsSync(STORE_FILE)) {
      // First run: auto-install default agents
      const defaults = getDefaultInstallations();
      saveToDisk(defaults);
      installed = defaults;
      return defaults;
    }
    const raw = readFileSync(STORE_FILE, "utf-8");
    const parsed: InstalledAgentsFile = JSON.parse(raw);
    if (!parsed.agents || parsed.agents.length === 0) {
      // Empty file/migration: auto-install defaults
      const defaults = getDefaultInstallations();
      saveToDisk(defaults);
      installed = defaults;
      return defaults;
    }
    installed = parsed.agents;
  } catch (err) {
    console.log(`[agents-store] failed to load installed agents: ${err}`);
    installed = [];
  }
  return installed;
}

function saveToDisk(agents: InstalledAgent[]): void {
  ensureDir();
  try {
    const data: InstalledAgentsFile = { agents };
    writeFileSync(STORE_FILE, JSON.stringify(data, null, 2), "utf-8");
    installed = agents;
  } catch (err) {
    console.log(`[agents-store] failed to save: ${err}`);
  }
}

/**
 * On first run, auto-install common agents that might be on the user's PATH.
 * This ensures a smooth upgrade from the old PATH-scanning behavior.
 */
function getDefaultInstallations(): InstalledAgent[] {
  const defaults: string[] = ["opencode", "claude", "codex-acp"];
  const now = Date.now();
  return defaults
    .map((agentId) => ({
      agentId,
      installedAt: now,
      source: "registry" as const,
    }))
    .filter((a) => getRegistryAgent(a.agentId) !== undefined);
}

// ── Public API ────────────────────────────────────────────────────────

export function getInstalledAgents(): InstalledAgent[] {
  return [...loadFromDisk()];
}

export function isAgentInstalled(agentId: string): boolean {
  return loadFromDisk().some((a) => a.agentId === agentId);
}

export function installAgent(
  agentId: string,
  source: "registry" | "custom" = "registry",
  options?: { command?: string; args?: string[]; env?: Record<string, string> },
): void {
  const agents = loadFromDisk();
  if (agents.some((a) => a.agentId === agentId)) {
    console.log(`[agents-store] agent ${agentId} already installed`);
    return;
  }
  const entry: InstalledAgent = {
    agentId,
    installedAt: Date.now(),
    source,
  };
  if (source === "custom") {
    entry.customCommand = options?.command;
    entry.customArgs = options?.args;
    entry.customEnv = options?.env;
  }
  agents.push(entry);
  saveToDisk(agents);
  console.log(`[agents-store] installed agent: ${agentId}`);
}

export function uninstallAgent(agentId: string): boolean {
  const agents = loadFromDisk();
  const idx = agents.findIndex((a) => a.agentId === agentId);
  if (idx < 0) return false;
  agents.splice(idx, 1);
  saveToDisk(agents);
  console.log(`[agents-store] uninstalled agent: ${agentId}`);
  return true;
}

export function setAgentPinned(agentId: string, pinned: boolean): void {
  const agents = loadFromDisk();
  const agent = agents.find((a) => a.agentId === agentId);
  if (agent) {
    agent.pinned = pinned;
    saveToDisk(agents);
  }
}

export function setAgentEnvOverrides(agentId: string, env: Record<string, string>): void {
  const agents = loadFromDisk();
  const agent = agents.find((a) => a.agentId === agentId);
  if (agent) {
    agent.customEnv = { ...(agent.customEnv || {}), ...env };
    saveToDisk(agents);
  }
}

// ── Agent Resolution ──────────────────────────────────────────────────

export interface ResolvedAgentInfo {
  agentId: string;
  name: string;
  cmd: string;
  args: string[];
  env: Record<string, string>;
  source: "registry" | "custom";
}

/**
 * Resolve an agent's launch info from installed config + registry.
 * Returns null if agent is not installed or can't be resolved.
 */
export function resolveAgentInfo(agentId: string): ResolvedAgentInfo | null {
  const agents = loadFromDisk();
  const installedAgent = agents.find((a) => a.agentId === agentId);
  if (!installedAgent) return null;

  // Custom agent — use user-provided command/args
  if (installedAgent.source === "custom") {
    if (!installedAgent.customCommand) return null;
    return {
      agentId,
      name: agentId,
      cmd: installedAgent.customCommand,
      args: installedAgent.customArgs || [],
      env: installedAgent.customEnv || {},
      source: "custom",
    };
  }

  // Registry agent — resolve from registry
  const name = getAgentDisplayName(agentId);
  const resolved = resolveAgentCommand(agentId);
  if (!resolved) return null;

  return {
    agentId,
    name,
    cmd: resolved.cmd,
    args: resolved.args,
    env: { ...(resolved.env || {}), ...(installedAgent.customEnv || {}) },
    source: "registry",
  };
}

export function isValidAgent(agentId: string): boolean {
  return isAgentInstalled(agentId);
}

export function getAgentLaunchArgs(agentName: string): string[] {
  // Compatibility shim for old code that calls getAgentLaunchArgs
  const info = resolveAgentInfo(agentName);
  if (!info) return ["acp"];
  return info.args;
}