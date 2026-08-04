import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";

export async function handleSetConfig(
  ws: WebSocket,
  sessionId: string,
  configId: string,
  value: string,
): Promise<void> {
  try {
    const result = await sessionManager.setConfig(sessionId, configId, value, ws);
    try {
      ws.send(JSON.stringify({
        type: "config_option_updated",
        sessionId,
        configOptions: result,
      }));
    } catch {}
  } catch (err: any) {
    const msg = err instanceof Error ? err.message : String(err);
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: `set_config failed: ${msg}` })); } catch {}
  }
}
