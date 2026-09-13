import type { AcpClient } from "./acp/client.mjs";
import { createTempClient } from "./temp-client.mjs";
import { getInstalledAgents, installAgent as storeInstallAgent, uninstallAgent as storeUninstallAgent, resolveAgentRuntime, type InstalledAgent } from "./agents-store.mjs";
import { extractModelList, queryModelListOnce, type ModelList } from "./model-list.mjs";
import { resolveWorkspacePath, canonicalizeWorkspacePath, areWorkspacePathsEqual } from "./path-utils.mjs";

const LIST_TIMEOUT = 4000;

function withTimeout<T>(promise: Promise<T>, label: string): Promise<T> {
  let timer: ReturnType<typeof setTimeout>;
  return Promise.race([
    promise,
    new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label} timeout`)), LIST_TIMEOUT);
    }),
  ]).finally(() => clearTimeout(timer));
}

/**
 * Central service for agent lifecycle operations.
 *
 * Encapsulates temp client spawning and bounded one-shot queries,
 * custom command args resolution (via createTempClient → getAgentLaunchArgs),
 * and cross-platform cwd path normalization.
 *
 * Future: will consume SessionManager with AcpClientFactory DI for
 * session-aware client reuse.
 */
class AgentRegistryService {
  /**
   * Returns the list of installed agents from the local store.
   */
  listInstalledAgents(): InstalledAgent[] {
    return getInstalledAgents();
  }

  /**
   * Queries all installed agents (or a single agentFilter) for sessions,
   * spawning temp ACP clients. Returns sessions sorted newest-first.
   *
   * - Creates temp clients for each agent
   * - Wraps each listSessions call in a 12-second Promise.race timeout
   * - Filters sessions by resolved cwd when `cwd` is provided
   * - Normalizes cwd paths across Windows and POSIX home aliases
   * - Attaches agent metadata to each session
   */
  async queryAggregateSessions(
    cwd?: string,
    agentFilter?: string,
  ): Promise<any[]> {
    const installed = (agentFilter
      ? getInstalledAgents().filter((a) => a.agentId === agentFilter)
      : getInstalledAgents()).filter((item) => {
        const runtime = resolveAgentRuntime(item.agentId);
        return runtime?.native.enabled === true && runtime.executablePath !== null;
      });
    const allSessions: any[] = [];
    const resolvedCwd = resolveWorkspacePath(cwd);
    const targetCwd = resolvedCwd ? canonicalizeWorkspacePath(resolvedCwd) : null;

    await Promise.all(
      installed.map(async (agentItem) => {
        let temp: { client: AcpClient; destroy: () => void } | null = null;
        try {
          temp = await createTempClient(agentItem.agentId, resolvedCwd);
          const result = await withTimeout(
            temp.client.listSessions(resolvedCwd),
            "listSessions",
          );
          const sessions = (result as any).sessions || [];
          for (const s of sessions) {
            if (targetCwd && s.cwd) {
              // Platform-aware comparison: Windows folds case, POSIX does not.
              const sessionCwd = resolveWorkspacePath(s.cwd);
              if (!sessionCwd || !areWorkspacePathsEqual(sessionCwd, targetCwd)) continue;
            }
            s.agent = agentItem.agentId;
            if (!s.createdAt && s.updatedAt) {
              s.createdAt = new Date(s.updatedAt).getTime();
            }
            allSessions.push(s);
          }

        } catch (err: any) {
          console.log(
            `[server] aggregate listSessions error for agent "${agentItem.agentId}": ${err.message}`,
          );
        } finally {
          if (temp) temp.destroy();
        }
      }),
    );

    allSessions.sort(
      (a, b) => (b.createdAt || 0) - (a.createdAt || 0),
    );
    return allSessions;
  }

  /**
   * Fetches the model/ mode list for an agent.
   *
   * Spawns a temp ACP client (or reuses existingClient if provided),
   * creates a session to extract model list, then cleans up.
   * Wrapped in queryModelListOnce for cache dedup.
   */
  async listModels(
    agent: string,
    cwd?: string,
    refresh: boolean = false,
    existingClient?: AcpClient,
  ): Promise<ModelList> {
    const runtime = resolveAgentRuntime(agent);
    if (!runtime?.native.enabled || !runtime.native.modelSelection || !runtime.executablePath) {
      return { models: [], modes: [] };
    }
    return await queryModelListOnce(agent, cwd, refresh, async () => {
      const { client, destroy } = existingClient
        ? { client: existingClient, destroy: () => {} }
        : await createTempClient(agent, cwd);
      try {
        const result = await withTimeout(client.createSession(cwd || ""), "createSession");
        const sessionId = (result as any).sessionId;
        const list = extractModelList(result);
        if (sessionId) {
          client.closeSession(sessionId).catch(() => {});
        }
        return list;
      } finally {
        destroy();
      }
    });
  }

  /** Install an agent from the registry into the local installed store. */
  installAgent(agentId: string): boolean {
    return storeInstallAgent(agentId, "registry");
  }

  /** Uninstall an agent. Returns true if the agent was found and removed. */
  uninstallAgent(agentId: string): boolean {
    return storeUninstallAgent(agentId);
  }

  /** Install a custom agent with explicit command and args. */
  installCustomAgent(
    name: string,
    options: { command: string; args?: string[]; env?: Record<string, string> },
  ): boolean {
    return storeInstallAgent(name, "custom", options);
  }
}

export const agentRegistry = new AgentRegistryService();
