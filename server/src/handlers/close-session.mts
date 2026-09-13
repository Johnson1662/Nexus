import type { WebSocket } from "ws";
import { SessionOperationError, SessionOwnerError, sessionManager } from "../session-manager.mjs";
import { HerdrAdapter, HerdrStreamer } from "../discovery/herdr-adapter.mjs";
import { HerdrTailerRegistry } from "../discovery/herdr-session-tailer.mjs";

const externalClosingSessions = new Set<string>();

export function markExternalSessionClosing(sessionId: string): void {
  externalClosingSessions.add(sessionId);
}

export function isExternalSessionClosing(sessionId: string): boolean {
  return externalClosingSessions.has(sessionId);
}

export function unmarkExternalSessionClosing(sessionId: string): void {
  externalClosingSessions.delete(sessionId);
}

export async function handleCloseSession(
  ws: WebSocket,
  sessionId: string,
): Promise<void> {
  try {
    await doCloseSession(ws, sessionId);
  } finally {
    unmarkExternalSessionClosing(sessionId);
  }
}

async function doCloseSession(
  ws: WebSocket,
  sessionId: string,
): Promise<void> {
  if (!sessionId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId is required" })); } catch {}
    return;
  }
  if (sessionId.startsWith("ambient:")) {
    HerdrTailerRegistry.get(sessionId)?.destroy();
    try {
      ws.send(JSON.stringify({ type: "session_closed", sessionId }));
    } catch {}
    return;
  }
  if (sessionId.startsWith("herdr:")) {
    const paneId = sessionId.slice("herdr:".length);
    try {
      await HerdrAdapter.closePane(paneId);
      HerdrTailerRegistry.get(sessionId)?.destroy();
      HerdrStreamer.stop(paneId);
      try { ws.send(JSON.stringify({ type: "session_closed", sessionId })); } catch {}
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      try { ws.send(JSON.stringify({ type: "error", sessionId, code: "HERDR_CLOSE_FAILED", text: message })); } catch {}
    }
    return;
  }
  try {
    await sessionManager.close(sessionId, ws);
    try { ws.send(JSON.stringify({ type: "session_closed", sessionId })); } catch {}
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    const code = err instanceof SessionOwnerError || err instanceof SessionOperationError
      ? err.code
      : "SESSION_ACCESS_DENIED";
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: msg })); } catch {}
  }
}
