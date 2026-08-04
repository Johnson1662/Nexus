import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";

export async function handleLoadSession(
  ws: WebSocket,
  params: {
    sessionId: string;
    cwd?: string;
    agent?: string;
    model?: string;
    lastMessageId?: string;
  },
): Promise<void> {
  const { sessionId: targetSessionId, cwd, agent = "opencode", model, lastMessageId } = params;

  if (!targetSessionId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId is required" })); } catch {}
    return;
  }

  let sess;
  try {
    sess = await sessionManager.getOrCreate(ws, {
      agent, cwd, model,
      sessionId: targetSessionId,
      mode: "load",
    });
  } catch (err: unknown) {
    const code = typeof err === "object" && err && "code" in err ? String(err.code) : "SESSION_ACCESS_DENIED";
    const message = err instanceof Error ? err.message : String(err);
    try { ws.send(JSON.stringify({ type: "error", sessionId: targetSessionId, code, text: message })); } catch {}
    return;
  }

  const sessionId = sess.sessionId;
  try {
    ws.send(JSON.stringify({
      type: "session_started",
      sessionId,
      agent,
      resumed: true,
      ...(model ? { model } : {}),
    }));
  } catch { /* WS gone */ }

  // Replay buffered events since lastMessageId
  if (lastMessageId) {
    const syncResult = sessionManager.replayBuffer(sessionId, lastMessageId, ws);
    if (syncResult.entries.length > 0) {
      const safeEntries = syncResult.entries
        .map(e => {
          try {
            const parsed = JSON.parse(e.payload);
            const payload = parsed.event || parsed;
            if (payload && typeof payload === "object") {
              payload.messageId = e.messageId;
            }
            return { messageId: e.messageId, payload, timestamp: e.timestamp };
          } catch {
            return null;
          }
        })
        .filter(Boolean);
      try {
        ws.send(JSON.stringify({
          type: "sync_response",
          sessionId,
          entries: safeEntries,
          overflow: syncResult.overflow,
        }));
      } catch { /* WS gone */ }
    }
  }
}
