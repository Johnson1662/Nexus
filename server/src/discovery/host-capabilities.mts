import { findExecutable, findAgentExecutable, isAgentInstalled } from "../agents-store.mjs";
import { listRegistryAgents, loadRegistry } from "../registry/registry.mjs";
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
    reason?: string;
  };
  herdr: {
    supported: boolean;
    ready: boolean;
    kind?: string;
    integrationId?: string;
    integrationInstalled?: boolean;
    executableSource?: "override" | "config" | "registry" | "known_location";
    reason?: string;
  };
  structuredHistory: boolean;
  modelSelection: boolean;
  modeSelection: boolean;
  authentication: boolean;
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
    const resolvedExec = findAgentExecutable(agent.id);
    const execPath = resolvedExec?.path ?? null;
    const nativeSupported = Boolean(agent.native?.enabled);
    const nativeReady = nativeSupported && execPath !== null;
    const herdrSupported = Boolean(agent.herdr?.enabled);
    const herdrReady = herdrAvailable && execPath !== null;
    const integrationId = agent.herdr?.integration ?? agent.id;
    const integrationInstalled = Boolean(integrations[integrationId]);

    return {
      id: agent.id,
      name: agent.name,
      enabled: isAgentInstalled(agent.id),
      native: {
        supported: nativeSupported,
        ready: nativeReady,
        executable: execPath ?? undefined,
        executableSource: resolvedExec?.source,
        reason: !nativeSupported
          ? "Native ACP not enabled for this agent"
          : execPath === null
            ? "Executable not found in PATH or known locations"
            : undefined,
      },
      herdr: {
        supported: herdrSupported,
        ready: herdrReady,
        kind: agent.herdr?.kind ?? agent.id,
        integrationId,
        integrationInstalled,
        executableSource: resolvedExec?.source,
        reason: !herdrAvailable
          ? "Herdr is not running on this host"
          : execPath === null
            ? "Executable not found in PATH or known locations"
            : undefined,
      },
      structuredHistory: agent.capabilities.structuredHistory,
      modelSelection: agent.capabilities.modelSelection,
      modeSelection: agent.capabilities.modeSelection,
      authentication: agent.capabilities.authentication,
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
