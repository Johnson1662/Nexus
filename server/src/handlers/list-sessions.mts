import type { WebSocket } from "ws";
import type { AcpClient } from "../acp/client.mjs";
import { findSessionForWs } from "../session.mjs";
import { createTempClient } from "../temp-client.mjs";
import { isValidAgent } from "../discovery/agents.mjs";
import { getInstalledAgents } from "../agents-store.mjs";
import { scanLocalSessionStatuses } from "../discovery/session-watcher.mjs";

export const sessionTitleOverrides = new Map<string, string>();

const sessionListCache = new Map<
  WebSocket,
  { sessions: any[]; timestamp: number; cwd?: string; agent?: string }
>();
const LIST_TIMEOUT = 5000;

export async function handleListSessions(
  ws: WebSocket,
  cwd?: string,
  agent?: string,
): Promise<void> {
  const sess = findSessionForWs(ws);

  // If a specific agent is requested, query only that agent
  if (agent) {
    if (!isValidAgent(agent)) {
      ws.send(JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }));
      return;
    }
    // Use active session's client if it matches the requested agent
    if (sess && sess.client?.connected && sess.agent === agent) {
      await doListSingleAgentSessions(ws, sess.client, agent, cwd);
      return;
    }
    let temp: { client: AcpClient; destroy: () => void } | null = null;
    try {
      temp = await createTempClient(agent, cwd);
      await doListSingleAgentSessions(ws, temp.client, agent, cwd);
    } catch (err: any) {
      console.log(`[server] list_sessions (single agent "${agent}") error: ${err.message}`);
      ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
    } finally {
      if (temp) temp.destroy();
    }
    return;
  }

  // No specific agent requested -> aggregate across ALL installed agents dynamically
  await doListAggregateSessions(ws, cwd);
}

async function doListSingleAgentSessions(
  ws: WebSocket,
  client: AcpClient,
  agent: string,
  cwd?: string,
): Promise<void> {
  const cached = sessionListCache.get(ws);
  if (
    cached &&
    cached.cwd === cwd &&
    cached.agent === agent &&
    Date.now() - cached.timestamp < 30000
  ) {
    const localStatuses = await scanLocalSessionStatuses();
    const statusMap = new Map(localStatuses.map((ls) => [ls.sessionId, ls.status]));
    for (const s of cached.sessions) {
      if (sessionTitleOverrides.has(s.sessionId)) {
        s.title = sessionTitleOverrides.get(s.sessionId);
      }
      if (statusMap.has(s.sessionId)) {
        s.status = statusMap.get(s.sessionId);
      }
    }
    ws.send(JSON.stringify({ type: "session_list", sessions: cached.sessions }));
    return;
  }

  try {
    const result = await Promise.race([
      client.listSessions(cwd),
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error("listSessions timeout")), LIST_TIMEOUT),
      ),
    ]);
    const sessions = (result as any).sessions || [];
    const localStatuses = await scanLocalSessionStatuses();
    const statusMap = new Map(localStatuses.map((ls) => [ls.sessionId, ls.status]));

    for (const s of sessions) {
      s.agent = agent;
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
    sessionListCache.set(ws, { sessions, timestamp: Date.now(), cwd, agent });
    ws.send(JSON.stringify({ type: "session_list", sessions }));
  } catch (err: any) {
    console.log(`[server] single listSessions error for "${agent}":`, err.message);
    ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
  }
}

async function doListAggregateSessions(
  ws: WebSocket,
  cwd?: string,
): Promise<void> {
  const cached = sessionListCache.get(ws);
  if (
    cached &&
    cached.cwd === cwd &&
    !cached.agent &&
    Date.now() - cached.timestamp < 30000
  ) {
    const localStatuses = await scanLocalSessionStatuses();
    const statusMap = new Map(localStatuses.map((ls) => [ls.sessionId, ls.status]));
    for (const s of cached.sessions) {
      if (sessionTitleOverrides.has(s.sessionId)) {
        s.title = sessionTitleOverrides.get(s.sessionId);
      }
      if (statusMap.has(s.sessionId)) {
        s.status = statusMap.get(s.sessionId);
      }
    }
    ws.send(JSON.stringify({ type: "session_list", sessions: cached.sessions }));
    return;
  }

  const installed = getInstalledAgents();
  const allSessions: any[] = [];
  const localStatuses = await scanLocalSessionStatuses();
  const statusMap = new Map(localStatuses.map((ls) => [ls.sessionId, ls.status]));

  await Promise.all(
    installed.map(async (agentItem) => {
      let temp: { client: AcpClient; destroy: () => void } | null = null;
      try {
        temp = await createTempClient(agentItem.agentId, cwd);
        const result = await Promise.race([
          temp.client.listSessions(cwd),
          new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error("listSessions timeout")), LIST_TIMEOUT),
          ),
        ]);
        const sessions = (result as any).sessions || [];
        for (const s of sessions) {
          s.agent = agentItem.agentId;
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
          allSessions.push(s);
        }
      } catch (err: any) {
        console.log(`[server] aggregate listSessions error for agent "${agentItem.agentId}": ${err.message}`);
      } finally {
        if (temp) temp.destroy();
      }
    }),
  );

  // Sort sessions by creation/update time descending
  allSessions.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));

  sessionListCache.set(ws, { sessions: allSessions, timestamp: Date.now(), cwd });
  ws.send(JSON.stringify({ type: "session_list", sessions: allSessions }));
}

export function clearSessionListCache(ws: WebSocket): void {
  sessionListCache.delete(ws);
}
