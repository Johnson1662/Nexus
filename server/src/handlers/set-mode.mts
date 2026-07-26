import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";

export async function handleSetMode(
  ws: WebSocket,
  sessionId: string,
  modeId: string,
): Promise<void> {
  if (!sessionId || !modeId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId and modeId are required" })); } catch {}
    return;
  }
  try {
    await sessionManager.setMode(sessionId, modeId);
    try { ws.send(JSON.stringify({ type: "mode_set", sessionId, modeId })); } catch {}
  } catch (err: any) {
    try { ws.send(JSON.stringify({ type: "error", text: `set_mode failed: ${err.message}` })); } catch {}
  }
}
