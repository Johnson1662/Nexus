import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";

export async function handleAuth(
  ws: WebSocket,
  sessionId: string,
  methodId: string,
): Promise<void> {
  const sess = sessionManager.getSession(sessionId);
  if (!sess) {
    ws.send(JSON.stringify({ type: "error", text: "session not found" }));
    return;
  }

  try {
    const result = await sess.client.authenticate(methodId);
    ws.send(JSON.stringify({ type: "auth_result", sessionId, result }));
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    ws.send(JSON.stringify({ type: "error", text: `auth failed: ${msg}` }));
  }
}
