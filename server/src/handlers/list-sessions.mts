import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { isValidAgent } from "../discovery/agents.mjs";
import { scanLocalSessionStatuses, mergeSessionStatus } from "../discovery/session-watcher.mjs";
import { agentRegistry } from "../agent-registry-service.mjs";
import { applyTitles } from "../session-titles.mjs";
import { resolveWorkspacePath } from "../path-utils.mjs";

export async function handleListSessions(
  ws: WebSocket,
  cwd?: string,
  agent?: string,
): Promise<void> {
  const sess = sessionManager.findSessionForWs(ws);
  const resolvedCwd = resolveWorkspacePath(cwd);
  let sessions: any[];

  if (agent) {
    if (!isValidAgent(agent)) {
      ws.send(
        JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }),
      );
      return;
    }
    if (sess?.client?.connected && sess.agent === agent) {
      let timeout: ReturnType<typeof setTimeout> | undefined;
      try {
        const result = await Promise.race([
          sess.client.listSessions(resolvedCwd),
          new Promise<never>((_, reject) => {
            timeout = setTimeout(() => reject(new Error("listSessions timeout")), 12000);
          }),
        ]);
        sessions = ((result as any).sessions || []).map((s: any) => ({
          ...s,
          agent,
        }));
      } catch {
        ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
        return;
      } finally {
        clearTimeout(timeout);
      }
    } else {
      sessions = await agentRegistry.queryAggregateSessions(resolvedCwd, agent);
    }
  } else {
    sessions = await agentRegistry.queryAggregateSessions(resolvedCwd);
  }

  // Apply persisted title overrides and local session statuses
  applyTitles(sessions);
  const localStatuses = await scanLocalSessionStatuses();
  // Filter filesystem statuses through canonical session identity so static
  // labels (e.g. "opencode-active") never attach to unrelated ACP session IDs.
  const knownIds = new Set(sessionManager.getAllSessions().keys());
  const activeIds = sessionManager.getActiveSessionIds();
  const canonicalStatuses = mergeSessionStatus(localStatuses, activeIds, knownIds);
  const statusMap = new Map(
    canonicalStatuses.map((ls: any) => [ls.sessionId, ls]),
  );
  for (const s of sessions) {
    const localStatus = statusMap.get(s.sessionId);
    if (localStatus) {
      s.status = localStatus.status;
      s.lastActivity = localStatus.lastActivity;
    } else if (!s.status) {
      s.status = "idle";
    }
    if (!s.createdAt && s.updatedAt) {
      s.createdAt = new Date(s.updatedAt).getTime();
    }
  }

  ws.send(JSON.stringify({ type: "session_list", sessions }));
}
