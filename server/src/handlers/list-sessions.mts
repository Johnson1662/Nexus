import type { WebSocket } from "ws";
import { findSessionForWs } from "../session.mjs";

const sessionListCache = new Map<WebSocket, { sessions: any[]; timestamp: number; cwd?: string }>();

export async function handleListSessions(
  ws: WebSocket,
  cwd?: string,
): Promise<void> {
  const sess = findSessionForWs(ws);
  if (!sess) {
    ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
    return;
  }

  const cached = sessionListCache.get(ws);
  if (cached && cached.cwd === cwd && Date.now() - cached.timestamp < 30000) {
    ws.send(JSON.stringify({ type: "session_list", sessions: cached.sessions }));
    return;
  }

  ws.send(JSON.stringify({ type: "session_list", sessions: [] }));

  try {
    const result = await sess.client.listSessions(cwd);
    const sessions = result.sessions || [];
    sessionListCache.set(ws, { sessions, timestamp: Date.now(), cwd });
    ws.send(JSON.stringify({ type: "session_list", sessions }));
  } catch (err: any) {
    console.log(`[server] list_sessions error: ${err.message}`);
  }
}

export function clearSessionListCache(ws: WebSocket): void {
  sessionListCache.delete(ws);
}
