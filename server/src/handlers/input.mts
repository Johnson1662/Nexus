import type { WebSocket } from "ws";
import { SessionOperationError, SessionOwnerError, sessionManager } from "../session-manager.mjs";
import { HerdrAdapter } from "../discovery/herdr-adapter.mjs";
import { HerdrTailerRegistry } from "../discovery/herdr-session-tailer.mjs";
import { sendAmbientCommand } from "../discovery/ambient-session.mjs";
import { isExternalSessionClosing } from "./close-session.mjs";

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

  if (sessionId.startsWith("ambient:")) {
    const tailer = HerdrTailerRegistry.get(sessionId);
    HerdrTailerRegistry.recordPendingPrompt(sessionId, text, ws);
    sendAmbientCommand(sessionId, { type: "prompt", text })
      .then(() => {
        tailer?.setLastInjectedPrompt(text, ws);
        try {
          ws.send(JSON.stringify({ type: "input_ack", sessionId }));
        } catch { /* WS gone */ }
      })
      .catch((err) => {
        console.log(`[input] Ambient sendPrompt error: ${err}`);
        try {
          ws.send(JSON.stringify({
            type: "error",
            sessionId,
            text: `Ambient prompt failed: ${String(err)}`,
          }));
        } catch { /* WS gone */ }
      });
    return;
  }

  if (sessionId.startsWith("herdr:")) {
    if (isExternalSessionClosing(sessionId)) {
      try {
        ws.send(JSON.stringify({
          type: "error",
          sessionId,
          code: "SESSION_CLOSING",
          text: "Session is closing",
        }));
      } catch {}
      return;
    }
    const paneId = sessionId.slice("herdr:".length);
    const tailer = HerdrTailerRegistry.get(sessionId);
    HerdrTailerRegistry.recordPendingPrompt(sessionId, text, ws);
    HerdrAdapter.sendPrompt(paneId, text).then(() => {
      tailer?.setLastInjectedPrompt(text, ws);
      try { ws.send(JSON.stringify({ type: "input_ack", sessionId })); } catch { /* WS gone */ }
    }).catch((err) => {
      console.log(`[input] Herdr sendPrompt error: ${err}`);
      try {
        ws.send(JSON.stringify({
          type: "error",
          sessionId,
          text: `Herdr prompt failed: ${String(err)}`,
        }));
      } catch { /* WS gone */ }
    });
    return;
  }

  // 原子占用回合成功后立即 ACK，客户端收到即清除 15s 输入超时定时器
  let handle;
  try {
    handle = sessionManager.beginPrompt(sessionId, text, ws);
  } catch (err: unknown) {
    const code = err instanceof SessionOwnerError || err instanceof SessionOperationError
      ? err.code
      : "SESSION_ACCESS_DENIED";
    const message = err instanceof Error ? err.message : String(err);
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: message })); } catch { /* WS gone */ }
    return;
  }
  try {
    ws.send(JSON.stringify({ type: "input_ack", sessionId }));
  } catch { /* WS gone */ }
  void handle.run();
}
