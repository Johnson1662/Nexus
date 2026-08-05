import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { setTitle } from "../session-titles.mjs";

interface StartParams {
  agent?: string;
  prompt?: string;
  cwd?: string;
  model?: string;
}

export async function handleStart(
  ws: WebSocket,
  params: StartParams,
): Promise<void> {
  const { agent = "opencode", prompt, cwd, model } = params;

  let sess;
  try {
    sess = await sessionManager.getOrCreate(ws, {
      agent, cwd, model,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    try { ws.send(JSON.stringify({ type: "start_failed", code: "AGENT_START_FAILED", text: message })); } catch {}
    return;
  }

  const sessionId = sess.sessionId;
  if (!sessionId) return;

  // Send session_started
  const sessionTitle = prompt
    ? prompt.slice(0, 50) + (prompt.length > 50 ? "…" : "")
    : "New Session";

  if (sessionId) {
    setTitle(sessionId, sessionTitle);
  }

  try {
    ws.send(JSON.stringify({
      type: "session_started",
      sessionId,
      agent,
      ...(prompt ? { prompt } : {}),
      ...(model ? { model } : {}),
      title: sessionTitle,
    }));
  } catch { /* WS gone */ }

  // If prompt was provided, dispatch it now
  if (prompt) {
    try {
      const handle = sessionManager.beginPrompt(sessionId, prompt, ws);
      void handle.run();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.log(`[handler:start] prompt dispatch error: ${msg}`);
      try {
        ws.send(JSON.stringify({ type: "error", sessionId, text: `Agent error: ${msg}` }));
      } catch { /* WS gone */ }
    }
  }
}
