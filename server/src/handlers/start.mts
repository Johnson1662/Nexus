import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { clearSessionListCache, sessionTitleOverrides } from "./list-sessions.mjs";

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

  const sess = await sessionManager.getOrCreate(ws, {
    agent, cwd, model,
  });

  const sessionId = sess.sessionId;
  if (!sessionId) return;

  // Send session_started
  const sessionTitle = prompt
    ? prompt.slice(0, 50) + (prompt.length > 50 ? "…" : "")
    : "New Session";

  if (sessionId) {
    sessionTitleOverrides.set(sessionId, sessionTitle);
    clearSessionListCache(ws);
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
      await sessionManager.dispatchPrompt(sessionId, prompt);
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.log(`[handler:start] prompt dispatch error: ${msg}`);
      try {
        ws.send(JSON.stringify({ type: "error", sessionId, text: `Agent error: ${msg}` }));
      } catch { /* WS gone */ }
    }
  }
}
