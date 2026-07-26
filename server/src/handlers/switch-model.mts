import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";

export async function handleSwitchModel(
  ws: WebSocket,
  sessionId: string,
  model: string,
): Promise<void> {
  try {
    await sessionManager.switchModel(sessionId, model);
    try { ws.send(JSON.stringify({ type: "model_switched", sessionId, model })); } catch {}
  } catch (err: any) {
    const msg = err instanceof Error ? err.message : String(err);
    try { ws.send(JSON.stringify({ type: "error", text: `model switch failed: ${msg}` })); } catch {}
  }
}
