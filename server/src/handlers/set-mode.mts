import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";

export async function handleSetMode(
  ws: WebSocket,
  sessionId: string,
  modeId: string,
): Promise<void> {
  if (!sessionId || !modeId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId and modeId are required" })); } catch {}
    return;
  }
  if (sessionId.startsWith("herdr:") || sessionId.startsWith("ambient:")) {
    try { ws.send(JSON.stringify({
      type: "error",
      sessionId,
      code: "MODE_SWITCH_UNSUPPORTED",
      text: "该终端会话的模式由 Agent 自身管理",
    })); } catch {}
    return;
  }
  try {
    await sessionManager.setMode(sessionId, modeId, ws);
    try { ws.send(JSON.stringify({ type: "mode_set", sessionId, modeId })); } catch {}
  } catch (err: any) {
    const message = err instanceof Error ? err.message : String(err);
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: `set_mode failed: ${message}` })); } catch {}
  }
}
