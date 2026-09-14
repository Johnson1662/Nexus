import { findExecutable, resolveAgentRuntime, getInstalledAgents } from "../agents-store.mjs";
import { listRegistryAgents, loadRegistry, getNativeConfig, getHerdrConfig } from "../registry/registry.mjs";
import { HerdrAdapter } from "./herdr-adapter.mjs";
import { checkNativeHookStatus } from "./native-hooks.mjs";
import { checkAcpAdapterStatus, resolveNativeAcpLaunch, checkNodeCompatibility } from "./acp-adapters.mjs";

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
    transport?: "cli";
    binary?: string;
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
    hookSupported: boolean;
    hookInstalled: boolean;
    hookState?: "not_installed" | "configured" | "active";
    hookDescription?: string;
    adapterRequired: boolean;
    adapterInstalled: boolean;
    adapterSource?: "managed" | "external" | "none";
    nodeCompatible: boolean;
    adapterPackage?: string;
    adapterBinary?: string;
  };
  herdr: {
    supported: boolean;
    ready: boolean;
    kind?: string;
    integrationId?: string;
    integrationInstalled?: boolean;
    /** current | not installed | outdated | missing | unknown | unsupported */
    integrationState?: string;
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

/**
 * Drop the cached snapshot. Call after anything that changes runtime
 * availability (agent install/uninstall, integration install) so the next
 * get/refresh reports the new state instead of a stale 3s window.
 */
export function invalidateHostCapabilities(): void {
  cachedCapabilities = null;
  lastDetectTime = 0;
}

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
  const integrationReport = await HerdrAdapter.listIntegrations();
  const integrationByTarget = new Map(
    integrationReport.integrations.map((entry) => [entry.target, entry]),
  );

  const agents: AgentRuntimeCapability[] = regAgents.map((agent) => {
    // Capability is a property of the agent, not of its install state, so the
    // resolver reports the executable even for agents this host has not
    // installed yet; `installed` is what the UI toggles.
    const runtime = resolveAgentRuntime(agent.id);
    const nativeCfg = runtime?.native ?? getNativeConfig(agent.id);
    const herdrCfg = runtime?.herdr ?? getHerdrConfig(agent.id);
    const execPath = runtime?.executablePath ?? null;
    const execSource = runtime?.executableSource ?? undefined;
    const nativeSupported = Boolean(nativeCfg?.enabled);
    const adapterStatus = checkAcpAdapterStatus(agent.id);
    const adapterRequired = adapterStatus.required;
    const adapterInstalled = adapterStatus.installed;
    const launch = resolveNativeAcpLaunch(agent.id);
    const nativeReady = launch.ok;

    let nativeReason: string | undefined;
    if (!nativeSupported) {
      nativeReason = "Native ACP not enabled for this agent";
    } else if (!launch.ok) {
      if (launch.code === "ADAPTER_MISSING") {
        nativeReason = `未安装 ACP 适配器 (${adapterStatus.package})`;
      } else if (launch.code === "NODE_INCOMPATIBLE") {
        const nodeCheck = checkNodeCompatibility(agent.id);
        nativeReason = `Node.js 版本不兼容 (当前: ${nodeCheck.version}, 需要: >= v${nodeCheck.minRequired}.0.0)`;
      } else if (launch.code === "CLI_MISSING") {
        nativeReason = "未在 PATH 中找到 Agent CLI 命令";
      } else {
        nativeReason = launch.error;
      }
    }

    const herdrSupported = Boolean(herdrCfg?.enabled);
    const herdrReady = herdrSupported && herdrAvailable && execPath !== null;
    const integrationId = runtime?.herdrIntegration ?? herdrCfg?.integration ?? undefined;
    const hookStatus = checkNativeHookStatus(agent.id);
    // Three states, never two: an unreadable status listing must not claim every
    // integration is missing (which would offer repairs that are not needed).
    const integrationEntry = integrationId ? integrationByTarget.get(integrationId) : undefined;
    const integrationState: AgentRuntimeCapability["herdr"]["integrationState"] = !integrationId
      ? "unsupported"
      : !integrationReport.parsed
        ? "unknown"
        : integrationEntry?.installed
          ? "current"
          : (integrationEntry?.state ?? "missing");
    const integrationInstalled = integrationState === "current";

    return {
      id: agent.id,
      name: agent.name,
      enabled: runtime?.installed ?? false,
      native: {
        supported: nativeSupported,
        ready: nativeReady,
        executable: execPath ?? undefined,
        executableSource: execSource,
        structuredHistory: nativeCfg?.structuredHistory ?? false,
        modelSelection: nativeCfg?.modelSelection ?? false,
        modeSelection: nativeCfg?.modeSelection ?? false,
        authentication: nativeCfg?.authentication ?? false,
        hookSupported: hookStatus.supported,
        hookInstalled: hookStatus.installed,
        hookState: hookStatus.state,
        hookDescription: hookStatus.description,
        adapterRequired,
        adapterInstalled,
        adapterSource: adapterStatus.source,
        nodeCompatible: adapterStatus.nodeCompatible,
        adapterPackage: adapterStatus.package,
        adapterBinary: adapterStatus.binary,
        reason: nativeReason,
      },
      herdr: {
        supported: herdrSupported,
        ready: herdrReady,
        kind: runtime?.herdrKind ?? herdrCfg?.kind ?? undefined,
        integrationId,
        integrationInstalled,
        integrationState,
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

  // Custom agents are installed by the user and are not in the registry. The
  // client's agent selectors read this list exclusively, so omitting them made a
  // successfully installed custom agent unselectable.
  const registryIds = new Set(regAgents.map((agent) => agent.id));
  for (const installed of getInstalledAgents()) {
    if (installed.source !== "custom" || registryIds.has(installed.agentId)) continue;
    const runtime = resolveAgentRuntime(installed.agentId);
    const execPath = runtime?.executablePath ?? null;
    agents.push({
      id: installed.agentId,
      name: installed.agentId,
      enabled: true,
      native: {
        supported: true,
        ready: execPath !== null,
        executable: execPath ?? undefined,
        executableSource: runtime?.executableSource ?? undefined,
        structuredHistory: false,
        modelSelection: true,
        modeSelection: true,
        authentication: true,
        hookSupported: false,
        hookInstalled: false,
        hookState: "not_installed",
        adapterRequired: false,
        adapterInstalled: true,
        adapterSource: "none",
        nodeCompatible: true,
        reason: execPath === null ? "Executable not found in PATH" : undefined,
      },
      herdr: {
        supported: false,
        ready: false,
        integrationInstalled: false,
        integrationState: "unsupported",
        structuredHistory: false,
        modelSelection: false,
        modeSelection: false,
        authentication: false,
        reason: "Custom agents are not part of the Herdr registry",
      },
    });
  }

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
      transport: "cli",
      binary: herdrProbe.binary,
      reason: herdrProbe.reason,
    },
    agents,
  };
  lastDetectTime = now;

  return cachedCapabilities;
}
