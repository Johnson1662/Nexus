import type { WebSocket } from "ws";
import { getSession } from "../session.mjs";

export function handleCancel(
  ws: WebSocket,
  sessionId: string,
): void {
  const sess = getSession(sessionId);
  if (!sess) return;

  sess.client.cancel(sess.acpSessionId).catch(() => {});
  ws.send(JSON.stringify({ type: "session_cancelled", sessionId }));
}
