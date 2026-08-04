import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";

export async function handleCloseSession(
  ws: WebSocket,
  sessionId: string,
): Promise<void> {
  if (!sessionId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId is required" })); } catch {}
    return;
  }
  try {
    await sessionManager.close(sessionId, ws);
    try { ws.send(JSON.stringify({ type: "session_closed", sessionId })); } catch {}
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: msg })); } catch {}
  }
}
