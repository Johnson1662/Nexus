import path from "node:path";
import type { AcpClient } from "./acp/client.mjs";
import { createTempClient } from "./temp-client.mjs";
import { getInstalledAgents, installAgent as storeInstallAgent, uninstallAgent as storeUninstallAgent, type InstalledAgent } from "./agents-store.mjs";
import { extractModelList, queryModelListOnce, type ModelList } from "./model-list.mjs";

const LIST_TIMEOUT = 12000;

/**
 * Central service for agent lifecycle operations.
 *
 * Encapsulates temp client spawning, 12-second Promise.race timeout safety,
 * custom command args resolution (via createTempClient → getAgentLaunchArgs),
 * and path.resolve(cwd).toLowerCase() path normalization.
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
   * - Normalizes cwd paths via path.resolve(cwd).toLowerCase()
   * - Attaches agent metadata to each session
   */
  async queryAggregateSessions(
    cwd?: string,
    agentFilter?: string,
  ): Promise<any[]> {
    const installed = agentFilter
      ? getInstalledAgents().filter((a) => a.agentId === agentFilter)
      : getInstalledAgents();
    const allSessions: any[] = [];
    const normalizedTargetCwd = cwd
      ? path.resolve(cwd).toLowerCase()
      : undefined;

    await Promise.all(
      installed.map(async (agentItem) => {
        let temp: { client: AcpClient; destroy: () => void } | null = null;
        try {
          temp = await createTempClient(agentItem.agentId, cwd);
          const result = await Promise.race([
            temp.client.listSessions(cwd),
            new Promise<never>((_, reject) =>
              setTimeout(
                () => reject(new Error("listSessions timeout")),
                LIST_TIMEOUT,
              ),
            ),
          ]);
          const sessions = (result as any).sessions || [];
          for (const s of sessions) {
            if (normalizedTargetCwd && s.cwd) {
              const normalizedSessionCwd = path
                .resolve(s.cwd)
                .toLowerCase();
              if (normalizedSessionCwd !== normalizedTargetCwd) continue;
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
    return await queryModelListOnce(agent, cwd, refresh, async () => {
      const { client, destroy } = existingClient
        ? { client: existingClient, destroy: () => {} }
        : await createTempClient(agent, cwd);
      try {
        const result = await client.createSession(cwd || "");
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
  installAgent(agentId: string): void {
    storeInstallAgent(agentId, "registry");
  }

  /** Uninstall an agent. Returns true if the agent was found and removed. */
  uninstallAgent(agentId: string): boolean {
    return storeUninstallAgent(agentId);
  }

  /** Install a custom agent with explicit command and args. */
  installCustomAgent(
    name: string,
    options: { command: string; args?: string[]; env?: Record<string, string> },
  ): void {
    storeInstallAgent(name, "custom", options);
  }
}

export const agentRegistry = new AgentRegistryService();
