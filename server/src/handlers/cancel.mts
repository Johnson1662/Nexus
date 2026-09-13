import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";
import { HerdrAdapter, isHerdrCode } from "../discovery/herdr-adapter.mjs";
import { sendAmbientCommand } from "../discovery/ambient-session.mjs";

export function handleCancel(
  ws: WebSocket,
  sessionId: string,
): void {
  if (sessionId.startsWith("ambient:")) {
    confirmAmbientCancel(ws, sessionId).catch((err) => {
      console.log(`[cancel] Ambient confirm error: ${err}`);
    });
    return;
  }

  if (sessionId.startsWith("herdr:")) {
    const paneId = sessionId.slice("herdr:".length);
    confirmHerdrCancel(ws, sessionId, paneId).catch((err) => {
      console.log(`[cancel] Herdr confirm error: ${err}`);
    });
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

function send(ws: WebSocket, payload: Record<string, unknown>): void {
  try {
    ws.send(JSON.stringify(payload));
  } catch { /* socket already gone */ }
}

async function confirmAmbientCancel(ws: WebSocket, sessionId: string): Promise<void> {
  try {
    await sendAmbientCommand(sessionId, { type: "cancel" });
    send(ws, { type: "session_cancelled", sessionId, accepted: true });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    send(ws, { type: "cancel_failed", sessionId, error: message });
  }
}

/**
 * Cancel a Herdr pane's turn and only report completion once Herdr itself
 * confirms the agent stopped.
 *
 * `agent_not_found` / `pane_not_found` both mean the turn cannot continue, so
 * `turn_ended` is the honest answer. Every other failure — missing binary,
 * timeout, unparsable output — is a failure to *verify*, reported as
 * `cancel_failed`, never as a completed turn.
 */
async function confirmHerdrCancel(ws: WebSocket, sessionId: string, paneId: string): Promise<void> {
  try {
    await HerdrAdapter.sendKeys(paneId, ["Ctrl+C"]);
  } catch (err) {
    if (isHerdrCode(err, "agent_not_found") || isHerdrCode(err, "pane_not_found")) {
      send(ws, { type: "turn_ended", sessionId, status: "gone" });
      return;
    }
    send(ws, { type: "cancel_failed", sessionId, error: herdrVerifyError(err) });
    return;
  }

  send(ws, { type: "session_cancelled", sessionId, accepted: true });

  try {
    const status = await HerdrAdapter.waitForStatus(paneId, ["idle", "done"], 8000);
    send(ws, { type: "turn_ended", sessionId, status });
    return;
  } catch (err) {
    if (isHerdrCode(err, "agent_not_found") || isHerdrCode(err, "pane_not_found")) {
      send(ws, { type: "turn_ended", sessionId, status: "gone" });
      return;
    }
  }

  // The wait timed out or failed at the transport level: distinguish "the pane
  // really is gone" from "we could not tell".
  try {
    await HerdrAdapter.getAgent(paneId);
  } catch (probeErr) {
    if (isHerdrCode(probeErr, "agent_not_found") || isHerdrCode(probeErr, "pane_not_found")) {
      send(ws, { type: "turn_ended", sessionId, status: "gone" });
      return;
    }
    send(ws, { type: "cancel_failed", sessionId, error: herdrVerifyError(probeErr) });
    return;
  }

  send(ws, {
    type: "cancel_failed",
    sessionId,
    status: "working",
    error: "Agent did not stop after cancel signal",
  });
}

function herdrVerifyError(err: unknown): string {
  const message = err instanceof Error ? err.message : String(err);
  return `VERIFY_FAILED: ${message}`;
}
