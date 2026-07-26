import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";

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
  sessionManager.dispatchPrompt(sessionId, text).catch((err: Error) => {
    console.log(`[handler:input] dispatchPrompt error: ${err.message}`);
    try {
      ws.send(JSON.stringify({ type: "error", sessionId, text: `Failed to process input: ${err.message}` }));
    } catch { /* WS gone */ }
  });
}
