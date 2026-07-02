import {
  getInstalledAgents,
  isAgentInstalled as storeIsAgentInstalled,
  resolveAgentInfo,
  getAgentLaunchArgs as storeGetAgentLaunchArgs,
} from "../agents-store.mjs";
import { loadRegistry, getRegistryAgent, listRegistryAgents, getAgentDisplayName } from "../registry/registry.mjs";

// ── Re-export types ───────────────────────────────────────────────────

export interface AgentInfo {
  name: string;
  title: string;
  version: string;
  source: string;
  binaryPath: string;
  installed: boolean;
}

// ── Agent list (from installed + registry) ────────────────────────────

/**
 * List all installed agents, enriched with registry metadata.
 * This replaces the old PATH-scanning approach.
 */
export function discoverAgents(): AgentInfo[] {
  loadRegistry();
  const installed = getInstalledAgents();
  return installed.map((entry) => {
    const reg = getRegistryAgent(entry.agentId);
    return {
      name: entry.agentId,
      title: reg?.name ?? entry.agentId,
      version: reg?.version ?? "unknown",
      source: entry.source,
      binaryPath: entry.customCommand || "",
      installed: true,
    };
  });
}

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

/**
 * Get launch args for an installed agent.
 * Falls back to ["acp"] if unknown (backward compat).
 */
export function getAgentLaunchArgs(agentName: string): string[] {
  return storeGetAgentLaunchArgs(agentName);
}
