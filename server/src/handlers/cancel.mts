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
      ws.send(JSON.stringify({ type: "session_cancelled", sessionId, accepted: true }));
    } catch {}

    pollHerdrCancelStatus(ws, sessionId, paneId);
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

function pollHerdrCancelStatus(ws: WebSocket, sessionId: string, paneId: string): void {
  const startTime = Date.now();
  const maxWaitMs = 9000;
  const pollIntervalMs = 300;

  const timer = setInterval(async () => {
    try {
      const agents = await HerdrAdapter.listAgents();
      const agent = agents.find((a) => a.pane_id === paneId);
      const status = agent?.agent_status;

      if (!agent || status === "idle" || status === "done") {
        clearInterval(timer);
        try {
          ws.send(JSON.stringify({ type: "turn_ended", sessionId, status: status || "idle" }));
        } catch {}
        return;
      }

      if (Date.now() - startTime >= maxWaitMs) {
        clearInterval(timer);
        try {
          ws.send(
            JSON.stringify({
              type: "cancel_failed",
              sessionId,
              status,
              error: "Agent did not stop after cancel signal",
            }),
          );
        } catch {}
      }
    } catch {
      if (Date.now() - startTime >= maxWaitMs) {
        clearInterval(timer);
        try {
          ws.send(
            JSON.stringify({
              type: "cancel_failed",
              sessionId,
              error: "Failed to verify agent stop status",
            }),
          );
        } catch {}
      }
    }
  }, pollIntervalMs);
}
