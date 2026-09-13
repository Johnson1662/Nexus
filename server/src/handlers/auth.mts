import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";

export async function handleAuth(
  ws: WebSocket,
  sessionId: string,
  methodId: string,
): Promise<void> {
  let sess;
  try {
    sess = sessionManager.assertOwner(sessionId, ws);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    try { ws.send(JSON.stringify({ type: "error", sessionId, code, text: message })); } catch {}
    return;
  }

  try {
    sess = await sessionManager.authenticatePending(sessionId, methodId, ws);
    ws.send(JSON.stringify({
      type: "auth_result",
      sessionId: sess.sessionId,
      configOptions: sess.client.configOptions,
    }));
    if (sessionId !== sess.sessionId) {
      ws.send(JSON.stringify({
        type: "session_started",
        sessionId: sess.sessionId,
        agent: sess.agent,
        title: "New Session",
        configOptions: sess.client.configOptions,
      }));
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    ws.send(JSON.stringify({ type: "error", sessionId, text: `auth failed: ${msg}` }));
  }
}
