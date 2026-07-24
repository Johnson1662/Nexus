import type { WebSocket } from "ws";
import { getSession } from "../session.mjs";
import { getLastModel, setLastModel } from "../prefs.mjs";

export async function handleSwitchModel(
  ws: WebSocket,
  sessionId: string,
  model: string,
): Promise<void> {
  const sess = getSession(sessionId);
  if (!sess || !sess.sessionId) {
    ws.send(
      JSON.stringify({ type: "error", text: `no active session: ${sessionId}` }),
    );
    return;
  }

  if (!model) {
    ws.send(JSON.stringify({ type: "error", text: "model is required" }));
    return;
  }

  try {
    console.log(`[server] switching model for ${sessionId} to ${model}`);
    await sess.client.setSessionModel(sess.sessionId, model);
    console.log(`[server] model switched for ${sessionId} to ${model}`);
    setLastModel(sess.agent || "opencode", model);
    ws.send(
      JSON.stringify({
        type: "model_switched",
        sessionId,
        model,
      }),
    );
  } catch (err: any) {
    console.log(`[server] switch_model error: ${err.message}`);
    ws.send(
      JSON.stringify({
        type: "error",
        text: `model switch failed: ${err.message}`,
      }),
    );
  }
}
