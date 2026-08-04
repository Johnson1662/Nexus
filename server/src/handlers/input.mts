import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";

export function handleInput(
  ws: WebSocket,
  sessionId: string,
  text: string,
): void {
  if (!sessionId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId is required" })); } catch {}
    return;
  }
  if (!text) {
    try { ws.send(JSON.stringify({ type: "error", sessionId, text: "text is required" })); } catch {}
    return;
  }
  sessionManager.dispatchPrompt(sessionId, text, ws).catch((err: Error) => {
    console.log(`[handler:input] dispatchPrompt error: ${err.message}`);
    try {
      const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
      ws.send(JSON.stringify({ type: "error", sessionId, code, text: `Failed to process input: ${err.message}` }));
    } catch { /* WS gone */ }
  });
}
