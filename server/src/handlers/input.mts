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
  // 参数与所有权校验通过后立即 ACK，客户端收到即清除 15s 输入超时定时器
  try {
    sessionManager.assertOwner(sessionId, ws);
  } catch (err: unknown) {
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    const message = err instanceof Error ? err.message : String(err);
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: message })); } catch { /* WS gone */ }
    return;
  }
  try {
    ws.send(JSON.stringify({ type: "input_ack", sessionId }));
  } catch { /* WS gone */ }
  sessionManager.dispatchPrompt(sessionId, text, ws).catch((err: Error) => {
    console.log(`[handler:input] dispatchPrompt error: ${err.message}`);
    try {
      const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
      ws.send(JSON.stringify({ type: "error", sessionId, code, text: `Failed to process input: ${err.message}` }));
    } catch { /* WS gone */ }
  });
}
