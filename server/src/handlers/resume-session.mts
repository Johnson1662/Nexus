import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";

export async function handleResumeSession(
  ws: WebSocket,
  params: {
    sessionId: string;
    cwd?: string;
    agent?: string;
    model?: string;
  },
): Promise<void> {
  const { sessionId: targetSessionId, cwd, agent = "opencode", model } = params;

  if (!targetSessionId) {
    try { ws.send(JSON.stringify({ type: "error", text: "sessionId is required" })); } catch {}
    return;
  }

  let sess;
  try {
    sess = await sessionManager.getOrCreate(ws, {
      agent, cwd, model,
      sessionId: targetSessionId,
      mode: "resume",
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
}
