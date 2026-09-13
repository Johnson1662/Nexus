import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";
import { HerdrAdapter } from "../discovery/herdr-adapter.mjs";
import { sendAmbientCommand } from "../discovery/ambient-session.mjs";

export function handleCancel(
  ws: WebSocket,
  sessionId: string,
): void {
  if (sessionId.startsWith("ambient:")) {
    sendAmbientCommand(sessionId, { type: "cancel" }).catch((err) => {
      console.log(`[cancel] Ambient sendCancel error: ${err}`);
    });
    try {
      ws.send(JSON.stringify({ type: "session_cancelled", sessionId }));
    } catch {}
    return;
  }

  if (sessionId.startsWith("herdr:")) {
    const paneId = sessionId.slice("herdr:".length);
    HerdrAdapter.sendKeys(paneId, ["Ctrl+C"]).catch((err) => {
      console.log(`[cancel] Herdr sendKeys error: ${err}`);
    });
    try {
      ws.send(JSON.stringify({ type: "session_cancelled", sessionId }));
    } catch {}
    return;
  }

  try {
    sessionManager.cancel(sessionId, ws);
    try { ws.send(JSON.stringify({ type: "session_cancelled", sessionId })); } catch {}
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: message })); } catch {}
  }
}
