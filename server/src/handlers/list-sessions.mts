import type { WebSocket } from "ws";
import type { AcpClient } from "../acp/client.mjs";
import { findSessionForWs } from "../session.mjs";
import { createTempClient } from "../temp-client.mjs";
import { isValidAgent } from "../discovery/agents.mjs";

const sessionListCache = new Map<WebSocket, { sessions: any[]; timestamp: number; cwd?: string }>();
const LIST_TIMEOUT = 10000;

export async function handleListSessions(
  ws: WebSocket,
  cwd?: string,
  agent?: string,
): Promise<void> {
  const sess = findSessionForWs(ws);

  // Use existing bridge session's client if alive
  if (sess && sess.client?.connected) {
    await doListSessions(ws, sess.client, cwd);
    return;
  }

  // Fall back to temporary ACP client
  if (!agent) {
    ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
    return;
  }

  if (!isValidAgent(agent)) {
    ws.send(JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }));
    return;
  }

  console.log(`[server] list_sessions: creating temp client for agent="${agent}"`);
  let temp: { client: AcpClient; destroy: () => void } | null = null;
  try {
    temp = await createTempClient(agent, cwd);
    await doListSessions(ws, temp.client, cwd);
  } catch (err: any) {
    console.log(`[server] list_sessions (temp) error: ${err.message}`);
    ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
  } finally {
    if (temp) temp.destroy();
  }
}

async function doListSessions(
  ws: WebSocket,
  client: AcpClient,
  cwd?: string,
): Promise<void> {
  const cached = sessionListCache.get(ws);
  if (cached && cached.cwd === cwd && Date.now() - cached.timestamp < 30000) {
    ws.send(JSON.stringify({ type: "session_list", sessions: cached.sessions }));
    return;
  }

  const result = await Promise.race([
    client.listSessions(cwd),
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("listSessions timeout")), LIST_TIMEOUT),
    ),
  ]);
  const sessions = (result as any).sessions || [];
  sessionListCache.set(ws, { sessions, timestamp: Date.now(), cwd });
  ws.send(JSON.stringify({ type: "session_list", sessions }));
}

export function clearSessionListCache(ws: WebSocket): void {
  sessionListCache.delete(ws);
}
