import {
  getInstalledAgents,
  isAgentInstalled as storeIsAgentInstalled,
  resolveAgentRuntime,
  type AgentRuntime,
} from "../agents-store.mjs";
import { loadRegistry, getRegistryAgent } from "../registry/registry.mjs";

// ── Re-export types ───────────────────────────────────────────────────

export interface AgentInfo {
  name: string;
  title: string;
  version: string;
  source: string;
  binaryPath: string;
  installed: boolean;
  ready: boolean;
  error?: string;
  native: AgentRuntime["native"];
  herdr: AgentRuntime["herdr"];
}

// ── Agent list (from installed + registry) ────────────────────────────

/**
 * List all installed agents, enriched with registry metadata.
 * Capabilities come from the shared runtime resolver so this list can never
 * disagree with HostCapabilities or with the launch path.
 */
export function discoverAgents(): AgentInfo[] {
  loadRegistry();
  const installed = getInstalledAgents();
  return installed.map((entry) => {
    const reg = getRegistryAgent(entry.agentId);
    const runtime = resolveAgentRuntime(entry.agentId);
    const ready = Boolean(runtime?.executablePath);
    return {
      name: entry.agentId,
      title: reg?.name ?? entry.agentId,
      version: reg?.version ?? "unknown",
      source: entry.source,
      binaryPath: runtime?.executablePath || "",
      installed: true,
      ready,
      ...(!ready
        ? { error: `Command not found: ${runtime?.cmd || entry.customCommand || entry.agentId}` }
        : {}),
      native: runtime?.native ?? FALLBACK_NATIVE,
      herdr: runtime?.herdr ?? FALLBACK_HERDR,
    };
  });
}

const FALLBACK_NATIVE: AgentRuntime["native"] = {
  enabled: true,
  structuredHistory: false,
  modelSelection: true,
  modeSelection: true,
  authentication: true,
};

const FALLBACK_HERDR: AgentRuntime["herdr"] = {
  enabled: false,
  structuredHistory: false,
  modelSelection: false,
  modeSelection: false,
  authentication: false,
};

/**
 * Force re-read installed config from disk.
 * (No-op in the new model — installed list is always up-to-date from disk.)
 */
export function refreshAgentCache(): AgentInfo[] {
  return discoverAgents();
}

// ── Agent lookup (delegated to agents-store + registry) ───────────────

/**
 * Whether this agent name is known (installed).
 */
export function isValidAgent(agentName: string): boolean {
  return storeIsAgentInstalled(agentName);
}
