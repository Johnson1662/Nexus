import type { WebSocket } from "ws";
import { findSessionForWs } from "../session.mjs";

const sessionListCache = new Map<WebSocket, { sessions: any[]; timestamp: number; cwd?: string }>();
const LIST_TIMEOUT = 10000; // 10 seconds

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

  try {
    const result = await Promise.race([
      sess.client.listSessions(cwd),
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error("listSessions timeout")), LIST_TIMEOUT)
      ),
    ]);
    const sessions = (result as any).sessions || [];
    sessionListCache.set(ws, { sessions, timestamp: Date.now(), cwd });
    ws.send(JSON.stringify({ type: "session_list", sessions }));
  } catch (err: any) {
    console.log(`[server] list_sessions error: ${err.message}`);
    ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
  }
}

export function clearSessionListCache(ws: WebSocket): void {
  sessionListCache.delete(ws);
}
