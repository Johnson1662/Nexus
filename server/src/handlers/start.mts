import type { WebSocket } from "ws";
import { AuthenticationRequiredError, sessionManager } from "../session-manager.mjs";
import { setTitle } from "../session-titles.mjs";
import { WorkspaceError } from "../path-utils.mjs";

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
  const { agent = "omp", prompt, cwd, model } = params;

  let sess;
  try {
    sess = await sessionManager.getOrCreate(ws, {
      agent, cwd, model,
    });
  } catch (err: unknown) {
    if (err instanceof AuthenticationRequiredError) {
      try {
        ws.send(JSON.stringify({
          type: "authentication_required",
          sessionId: err.sessionId,
          authMethods: err.authMethods,
          text: "Agent authentication required",
        }));
      } catch {}
      return;
    }
    const message = err instanceof Error ? err.message : String(err);
    const code = err instanceof WorkspaceError ? err.code : "AGENT_START_FAILED";
    try { ws.send(JSON.stringify({ type: "start_failed", code, text: message })); } catch {}
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
      authMethods: sess.client.authMethods,
      configOptions: sess.client.configOptions,
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
