import { readFileSync, writeFileSync, existsSync, mkdirSync, renameSync, unlinkSync, chmodSync } from "node:fs";
import path from "node:path";
import { homedir } from "node:os";
import {
  getRegistryAgent,
  resolveDistributionCommand,
  getAgentDisplayName,
  type AgentNativeConfig,
  type AgentHerdrConfig,
} from "./registry/registry.mjs";

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

const STORE_DIR = process.env.NEXUS_AGENTS_STORE_DIR ?? path.join(homedir(), ".nexus");
const STORE_FILE = path.join(STORE_DIR, "installed-agents.json");

let installed: InstalledAgent[] | null = null;

// ── Helpers ───────────────────────────────────────────────────────────

function ensureDir(): void {
  mkdirSync(STORE_DIR, { recursive: true });
  if (process.platform !== "win32") {
    try {
      chmodSync(STORE_DIR, 0o700);
    } catch {
      // Unix 权限设置尽力而为，不阻断存储目录创建。
    }
  }
}

export function findExecutable(command: string): string | null {
  return findExecutableDetailed(command)?.path ?? null;
}

/**
 * Like findExecutable, but reports whether the match came from PATH or from a
 * well-known user binary directory (used to expose executable provenance).
 */
export function findExecutableDetailed(
  command: string,
): { path: string; fromKnownLocation: boolean } | null {
  const names = process.platform === "win32" && !path.extname(command)
    ? (process.env.PATHEXT ?? ".EXE;.CMD;.BAT;.COM").split(";").map((ext) => command + ext.toLowerCase())
    : [command];
  if (path.isAbsolute(command) || command.includes("/") || command.includes("\\")) {
    const resolved = path.resolve(command);
    return existsSync(resolved) ? { path: resolved, fromKnownLocation: false } : null;
  }
  const searchGroups: Array<{ dirs: string[]; fromKnownLocation: boolean }> = [
    { dirs: (process.env.PATH ?? "").split(path.delimiter), fromKnownLocation: false },
    { dirs: knownBinDirs(), fromKnownLocation: true },
  ];
  for (const group of searchGroups) {
    for (const dir of group.dirs) {
      if (!dir) continue;
      for (const name of names) {
        const candidate = path.join(dir, name);
        if (existsSync(candidate)) return { path: candidate, fromKnownLocation: group.fromKnownLocation };
      }
    }
  }
  return null;
}

export function getNexusAdaptersDir(): string {
  return path.join(homedir(), ".nexus", "adapters");
}

export function getNexusAdaptersBinDir(): string {
  return path.join(getNexusAdaptersDir(), "node_modules", ".bin");
}

/**
 * Binary directories that exist regardless of how Nexus was launched.
 * Guards against a daemon started from a GUI/limited PATH.
 */
function knownBinDirs(): string[] {
  const home = homedir();
  if (process.platform === "win32") {
    return [
      getNexusAdaptersBinDir(),
      process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, "Programs") : "",
      process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, "Microsoft", "WindowsApps") : "",
      path.join(home, ".cargo", "bin"),
      process.env.APPDATA ? path.join(process.env.APPDATA, "npm") : "",
      path.join(home, ".bun", "bin"),
    ];
  }
  return [
    getNexusAdaptersBinDir(),
    path.join(home, ".local", "bin"),
    path.join(home, "bin"),
    "/usr/local/bin",
    "/opt/homebrew/bin",
    path.join(home, ".cargo", "bin"),
    path.join(home, ".bun", "bin"),
  ];
}

export type ExecutableSource = "override" | "config" | "registry" | "known_location";

export interface ResolvedExecutable {
  path: string;
  source: ExecutableSource;
}

/**
 * Resolve the CLI executable for a registry agent.
 * Order: env override → user config → registry detection/native → PATH + known dirs.
 * Returns null when nothing is found (caller decides how to degrade).
 */
export function findAgentExecutable(agentId: string): ResolvedExecutable | null {
  const registryAgent = getRegistryAgent(agentId);

  // 1. Explicit environment override: NEXUS_AGENT_<ID>_PATH
  const envKey = `NEXUS_AGENT_${agentId.toUpperCase().replace(/[^A-Z0-9]/g, "_")}_PATH`;
  const envOverride = process.env[envKey]?.trim();
  if (envOverride) {
    const found = findExecutable(envOverride);
    if (found) return { path: found, source: "override" };
  }

  // 2. Persisted per-user override
  const installedAgent = loadFromDisk().find((a) => a.agentId === agentId);
  const customCommand = installedAgent?.customCommand?.trim();
  if (customCommand) {
    const found = findExecutable(customCommand);
    if (found) return { path: found, source: "config" };
  }

  // 3. Registry candidates (detection aliases, then native command, then distribution)
  const isAdapterRequired = Boolean(registryAgent?.native?.adapterPackage);
  const candidates = [
    ...(registryAgent?.detection?.executables ?? []),
    ...(!isAdapterRequired && registryAgent?.native?.command ? [registryAgent.native.command] : []),
    ...(registryAgent?.distribution?.direct?.cmd ? [registryAgent.distribution.direct.cmd] : []),
  ];
  for (const candidate of candidates) {
    if (!candidate) continue;
    const found = findExecutableDetailed(candidate);
    if (found) {
      return { path: found.path, source: found.fromKnownLocation ? "known_location" : "registry" };
    }
  }

  return null;
}

function isValidStringRecord(value: unknown): value is Record<string, string> {
  return typeof value === "object"
    && value !== null
    && !Array.isArray(value)
    && Object.values(value).every((entry) => typeof entry === "string");
}

function isValidInstalledAgent(a: unknown): a is InstalledAgent {
  if (!a || typeof a !== "object" || Array.isArray(a)) return false;
  const agent = a as Record<string, unknown>;
  if (typeof agent.agentId !== "string" || agent.agentId.trim().length === 0) return false;
  if (agent.source !== "registry" && agent.source !== "custom") return false;
  if (agent.installedAt !== undefined && typeof agent.installedAt !== "number") return false;
  if (agent.customArgs !== undefined
      && (!Array.isArray(agent.customArgs) || !agent.customArgs.every((arg) => typeof arg === "string"))) {
    return false;
  }
  if (agent.customEnv !== undefined && !isValidStringRecord(agent.customEnv)) return false;
  if (agent.installedAt === undefined) agent.installedAt = Date.now();
  return true;
}

function loadFromDisk(): InstalledAgent[] {
  if (installed) return installed;
  ensureDir();
  try {
    if (!existsSync(STORE_FILE)) {
      // First run: auto-install default agents.
      // Set sentinel installed = [] first so any nested resolveAgentRuntime call
      // does not recursively re-enter loadFromDisk.
      installed = [];
      const defaults = getDefaultInstallations();
      saveToDisk(defaults);
      return defaults;
    }
    const raw = readFileSync(STORE_FILE, "utf-8");
    const parsed: unknown = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object" || !Array.isArray((parsed as { agents?: unknown }).agents)) {
      throw new Error("invalid installed agents file shape");
    }
    const entries = (parsed as { agents: unknown[] }).agents;
    // An explicit empty array must be respected — do not revive defaults.
    installed = entries.filter(isValidInstalledAgent);
  } catch (err) {
    console.log(`[agents-store] failed to load installed agents: ${err}`);
    installed = [];
  }
  return installed;
}

function saveToDisk(agents: InstalledAgent[]): boolean {
  const tmp = path.join(
    STORE_DIR,
    `.installed-agents-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.tmp`,
  );
  try {
    ensureDir();
    const data: InstalledAgentsFile = { agents };
    writeFileSync(tmp, JSON.stringify(data, null, 2), { encoding: "utf-8", mode: 0o600 });
    renameSync(tmp, STORE_FILE);
    if (process.platform !== "win32") {
      try {
        chmodSync(STORE_FILE, 0o600);
      } catch {
        // Unix 文件权限设置尽力而为，不影响已完成的原子写入。
      }
    }
    installed = agents;
    return true;
  } catch (err) {
    try {
      if (existsSync(tmp)) unlinkSync(tmp);
    } catch {
      // 临时文件清理失败时保留主错误日志，避免覆盖原始故障。
    }
    console.log(`[agents-store] failed to save: ${err}`);
    return false;
  }
}

/**
 * On first run, auto-install common agents that might be on the user's PATH.
 * This ensures a smooth upgrade from the old PATH-scanning behavior.
 */
function getDefaultInstallations(): InstalledAgent[] {
  const defaults: string[] = ["omp", "claude", "codex", "opencode"];
  const now = Date.now();
  return defaults
    .map((agentId) => ({
      agentId,
      installedAt: now,
      source: "registry" as const,
    }))
    .filter((a) => {
      const runtime = resolveAgentRuntime(a.agentId);
      return runtime !== null && runtime.executablePath !== null;
    });
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
): boolean {
  if (source === "custom") {
    const command = options?.command;
    if (!command || !findExecutable(command)) {
      throw new Error(`agent command not found in PATH: ${command || agentId}`);
    }
  } else {
    if (!getRegistryAgent(agentId)) {
      throw new Error(`unknown registry agent: ${agentId}`);
    }
  }
  const agents = loadFromDisk().map((agent) => ({ ...agent }));
  if (agents.some((a) => a.agentId === agentId)) {
    console.log(`[agents-store] agent ${agentId} already installed`);
    return true;
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
  if (!saveToDisk(agents)) return false;
  console.log(`[agents-store] installed agent: ${agentId}`);
  return true;
}

export function uninstallAgent(agentId: string): boolean {
  const agents = loadFromDisk().map((agent) => ({ ...agent }));
  const idx = agents.findIndex((a) => a.agentId === agentId);
  if (idx < 0) return false;
  agents.splice(idx, 1);
  const saved = saveToDisk(agents);
  if (saved) console.log(`[agents-store] uninstalled agent: ${agentId}`);
  return saved;
}

export function setAgentPinned(agentId: string, pinned: boolean): void {
  const agents = loadFromDisk().map((agent) => ({ ...agent }));
  const agent = agents.find((a) => a.agentId === agentId);
  if (agent) {
    agent.pinned = pinned;
    saveToDisk(agents);
  }
}

export function setAgentEnvOverrides(agentId: string, env: Record<string, string>): void {
  const agents = loadFromDisk().map((agent) => ({ ...agent }));
  const agent = agents.find((a) => a.agentId === agentId);
  if (agent) {
    agent.customEnv = { ...(agent.customEnv || {}), ...env };
    saveToDisk(agents);
  }
}

// ── Agent Resolution ──────────────────────────────────────────────────

export interface AgentRuntime {
  agentId: string;
  displayName: string;
  source: "registry" | "custom";
  installed: boolean;
  /**
   * The command to spawn. When the executable was resolved this is its absolute
   * path, so a PATH/alias/override resolution is honoured by the actual launch
   * instead of only by the capability probe.
   */
  cmd: string;
  args: string[];
  env: Record<string, string>;
  executablePath: string | null;
  executableSource: ExecutableSource | null;
  native: AgentNativeConfig;
  herdr: AgentHerdrConfig;
  herdrKind: string | null;
  herdrIntegration: string | null;
}

/**
 * Single resolution entry point for an agent's launch info, capabilities and
 * Herdr identity. Detection, install validation, Native launch and the agent
 * management UI all read this result so they can never disagree.
 *
 * Returns a result for any known agent — installed or not — so install
 * validation can use the same resolver. Returns null only for an unknown id.
 */
export function resolveAgentRuntime(agentId: string): AgentRuntime | null {
  const installedAgent = loadFromDisk().find((a) => a.agentId === agentId);
  const installed = installedAgent !== undefined;

  // Custom agent — use user-provided command/args
  if (installedAgent?.source === "custom") {
    if (!installedAgent.customCommand) return null;
    const found = findExecutableDetailed(installedAgent.customCommand);
    return {
      agentId,
      displayName: agentId,
      source: "custom",
      installed,
      cmd: found?.path ?? installedAgent.customCommand,
      args: installedAgent.customArgs || [],
      env: installedAgent.customEnv || {},
      executablePath: found?.path ?? null,
      executableSource: found ? (found.fromKnownLocation ? "known_location" : "config") : null,
      native: {
        enabled: true,
        command: installedAgent.customCommand,
        args: installedAgent.customArgs || [],
        structuredHistory: false,
        modelSelection: true,
        modeSelection: true,
        authentication: true,
      },
      herdr: {
        enabled: false,
        structuredHistory: false,
        modelSelection: false,
        modeSelection: false,
        authentication: false,
      },
      herdrKind: null,
      herdrIntegration: null,
    };
  }

  // Registry agent — resolve from registry
  const registryAgent = getRegistryAgent(agentId);
  const native = registryAgent?.native ?? null;
  const herdr = registryAgent?.herdr ?? null;
  if (!native || !herdr) return null;
  const resolved = resolveDistributionCommand(agentId);
  const found = findAgentExecutable(agentId);
  const fallbackCmd = resolved?.cmd ?? native.command ?? "";

  let nativeCmdPath: string | null = null;
  if (native.command) {
    const directAdapterPath = path.join(
      getNexusAdaptersBinDir(),
      process.platform === "win32" ? `${native.command}.cmd` : native.command,
    );
    if (existsSync(directAdapterPath)) {
      nativeCmdPath = directAdapterPath;
    } else {
      const foundNative = findExecutableDetailed(native.command);
      if (foundNative) {
        nativeCmdPath = foundNative.path;
      }
    }
  }

  return {
    agentId,
    displayName: getAgentDisplayName(agentId),
    source: "registry",
    installed,
    // Spawn exactly what was resolved; the bare command is only a fallback for
    // the message shown when nothing was found.
    cmd: nativeCmdPath ?? found?.path ?? fallbackCmd,
    args: resolved?.args ?? native.args ?? [],
    env: { ...(resolved?.env || {}), ...(installedAgent?.customEnv || {}) },
    executablePath: found?.path ?? null,
    executableSource: found?.source ?? null,
    native,
    herdr,
    herdrKind: herdr.kind ?? null,
    herdrIntegration: herdr.integration ?? null,
  };
}

export function isValidAgent(agentId: string): boolean {
  return isAgentInstalled(agentId);
}

export function _resetInstalledForTest(): void {
  installed = null;
}