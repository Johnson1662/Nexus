import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { isValidAgent } from "../discovery/agents.mjs";
import { scanLocalSessionStatuses } from "../discovery/session-watcher.mjs";
import { agentRegistry } from "../agent-registry-service.mjs";

export const sessionTitleOverrides = new Map<string, string>();

export async function handleListSessions(
  ws: WebSocket,
  cwd?: string,
  agent?: string,
): Promise<void> {
  const sess = sessionManager.findSessionForWs(ws);
  let sessions: any[];

  if (agent) {
    if (!isValidAgent(agent)) {
      ws.send(
        JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }),
      );
      return;
    }
    if (sess?.client?.connected && sess.agent === agent) {
      try {
        const result = await Promise.race([
          sess.client.listSessions(cwd),
          new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error("listSessions timeout")), 12000),
          ),
        ]);
        sessions = ((result as any).sessions || []).map((s: any) => ({
          ...s,
          agent,
        }));
      } catch {
        ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
        return;
      }
    } else {
      sessions = await agentRegistry.queryAggregateSessions(cwd, agent);
    }
  } else {
    sessions = await agentRegistry.queryAggregateSessions(cwd);
  }

  // Apply title overrides and local session statuses
  const localStatuses = await scanLocalSessionStatuses();
  const statusMap = new Map(
    localStatuses.map((ls: any) => [ls.sessionId, ls.status]),
  );
  for (const s of sessions) {
    if (sessionTitleOverrides.has(s.sessionId)) {
      s.title = sessionTitleOverrides.get(s.sessionId);
    }
    if (statusMap.has(s.sessionId)) {
      s.status = statusMap.get(s.sessionId);
    } else if (!s.status) {
      s.status = "idle";
    }
    if (!s.createdAt && s.updatedAt) {
      s.createdAt = new Date(s.updatedAt).getTime();
    }
  }

  ws.send(JSON.stringify({ type: "session_list", sessions }));
}

/**
 * Clears the per-WebSocket session list cache.
 * Previously used by the cache layer; kept as no-op for backward compatibility
 * with server.mts and start.mts callers.
 */
export function clearSessionListCache(_ws: WebSocket): void {
  // no-op — caching moved to agent-registry-service
}
