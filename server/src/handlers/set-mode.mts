import type { WebSocket } from "ws";
import { getSession } from "../session.mjs";

export async function handleSetMode(
  ws: WebSocket,
  sessionId: string,
  modeId: string,
): Promise<void> {
  const sess = getSession(sessionId);
  if (!sess || !sess.sessionId) {
    ws.send(JSON.stringify({ type: "error", text: "no active session" }));
    return;
  }
  try {
    await sess.client.setSessionMode(sess.sessionId, modeId);
    ws.send(JSON.stringify({ type: "mode_set", sessionId, modeId }));
  } catch (err: any) {
    ws.send(
      JSON.stringify({ type: "error", text: `set_mode failed: ${err.message}` }),
    );
  }
}
