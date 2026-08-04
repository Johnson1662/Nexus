import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";

export function handleCancel(
  ws: WebSocket,
  sessionId: string,
): void {
  try {
    sessionManager.cancel(sessionId, ws);
    try { ws.send(JSON.stringify({ type: "session_cancelled", sessionId })); } catch {}
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: message })); } catch {}
  }
}
