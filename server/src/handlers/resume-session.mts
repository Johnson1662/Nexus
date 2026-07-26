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

  const sess = await sessionManager.getOrCreate(ws, {
    agent, cwd, model,
    sessionId: targetSessionId,
    mode: "resume",
  });

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
