import { findExecutable, findAgentExecutable, resolveAgentRuntime } from "../agents-store.mjs";
import { listRegistryAgents, loadRegistry, getNativeConfig, getHerdrConfig } from "../registry/registry.mjs";
import { HerdrAdapter } from "./herdr-adapter.mjs";

export interface HostCapabilities {
  platform: "linux" | "darwin" | "win32";
  arch: string;
  git: {
    available: boolean;
    executable?: string;
    reason?: string;
  };
  herdr: {
    available: boolean;
    version?: string;
    session?: string;
    endpointKind?: "unix" | "pipe";
    reason?: string;
  };
  agents: AgentRuntimeCapability[];
}

export interface AgentRuntimeCapability {
  id: string;
  name: string;
  enabled: boolean;
  native: {
    supported: boolean;
    ready: boolean;
    executable?: string;
    executableSource?: "override" | "config" | "registry" | "known_location";
    structuredHistory: boolean;
    modelSelection: boolean;
    modeSelection: boolean;
    authentication: boolean;
    reason?: string;
  };
  herdr: {
    supported: boolean;
    ready: boolean;
    kind?: string;
    integrationId?: string;
    integrationInstalled?: boolean;
    executableSource?: "override" | "config" | "registry" | "known_location";
    structuredHistory: boolean;
    modelSelection: boolean;
    modeSelection: boolean;
    authentication: boolean;
    reason?: string;
  };
}

let cachedCapabilities: HostCapabilities | null = null;
let lastDetectTime = 0;
const CACHE_TTL_MS = 3000;

export async function detectHostCapabilities(forceRefresh = false): Promise<HostCapabilities> {
  const now = Date.now();
  if (!forceRefresh && cachedCapabilities && now - lastDetectTime < CACHE_TTL_MS) {
    return cachedCapabilities;
  }

  loadRegistry();
  const regAgents = listRegistryAgents();
  const gitPath = findExecutable("git");
  const herdrProbe = await HerdrAdapter.probe();
  const herdrAvailable = herdrProbe.available;
  const integrations = await HerdrAdapter.getIntegrationStatus();

  const agents: AgentRuntimeCapability[] = regAgents.map((agent) => {
    const runtime = resolveAgentRuntime(agent.id);
    // Capability is a property of the agent, not of its install state: fall
    // back to registry metadata when this host has not installed it yet.
    const nativeCfg = runtime?.native ?? getNativeConfig(agent.id);
    const herdrCfg = runtime?.herdr ?? getHerdrConfig(agent.id);
    const execPath = runtime ? runtime.executablePath : (findAgentExecutable(agent.id)?.path ?? null);
    const execSource = runtime?.executableSource ?? findAgentExecutable(agent.id)?.source ?? undefined;
    const nativeSupported = Boolean(nativeCfg?.enabled);
    const nativeReady = nativeSupported && execPath !== null;
    const herdrSupported = Boolean(herdrCfg?.enabled);
    const herdrReady = herdrSupported && herdrAvailable && execPath !== null;
    const integrationId = runtime?.herdrIntegration ?? herdrCfg?.integration ?? undefined;
    const integrationInstalled = integrationId ? Boolean(integrations[integrationId]) : false;

    return {
      id: agent.id,
      name: agent.name,
      enabled: runtime !== null,
      native: {
        supported: nativeSupported,
        ready: nativeReady,
        executable: execPath ?? undefined,
        executableSource: execSource,
        structuredHistory: nativeCfg?.structuredHistory ?? false,
        modelSelection: nativeCfg?.modelSelection ?? false,
        modeSelection: nativeCfg?.modeSelection ?? false,
        authentication: nativeCfg?.authentication ?? false,
        reason: !nativeSupported
          ? "Native ACP not enabled for this agent"
          : execPath === null
            ? "Executable not found in PATH or known locations"
            : undefined,
      },
      herdr: {
        supported: herdrSupported,
        ready: herdrReady,
        kind: runtime?.herdrKind ?? herdrCfg?.kind ?? undefined,
        integrationId,
        integrationInstalled,
        executableSource: execSource,
        structuredHistory: herdrCfg?.structuredHistory ?? false,
        modelSelection: herdrCfg?.modelSelection ?? false,
        modeSelection: herdrCfg?.modeSelection ?? false,
        authentication: herdrCfg?.authentication ?? false,
        reason: !herdrSupported
          ? "Herdr backend not enabled for this agent"
          : !herdrAvailable
            ? "Herdr is not running on this host"
            : execPath === null
              ? "Executable not found in PATH or known locations"
              : undefined,
      },
    };
  });

  const platform = (
    process.platform === "win32" ? "win32" : process.platform === "darwin" ? "darwin" : "linux"
  ) as "linux" | "darwin" | "win32";

  cachedCapabilities = {
    platform,
    arch: process.arch,
    git: {
      available: gitPath !== null,
      executable: gitPath ?? undefined,
      reason: gitPath === null ? "git executable not found in PATH" : undefined,
    },
    herdr: {
      available: herdrAvailable,
      version: herdrProbe.version,
      endpointKind: herdrProbe.endpointKind,
      reason: herdrProbe.reason,
    },
    agents,
  };
  lastDetectTime = now;

  return cachedCapabilities;
}
