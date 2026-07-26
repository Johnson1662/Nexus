import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";

export function handleCancel(
  ws: WebSocket,
  sessionId: string,
): void {
  sessionManager.cancel(sessionId);
  try { ws.send(JSON.stringify({ type: "session_cancelled", sessionId })); } catch {}
}
