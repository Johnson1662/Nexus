import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";

export async function handleSwitchModel(
  ws: WebSocket,
  sessionId: string,
  model: string,
): Promise<void> {
  try {
    await sessionManager.switchModel(sessionId, model, ws);
    try { ws.send(JSON.stringify({ type: "model_switched", sessionId, model })); } catch {}
  } catch (err: any) {
    const msg = err instanceof Error ? err.message : String(err);
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: `model switch failed: ${msg}` })); } catch {}
  }
}
