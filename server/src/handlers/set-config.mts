import type { WebSocket } from "ws";
import { getSession } from "../session.mjs";

export async function handleSetConfig(
  ws: WebSocket,
  sessionId: string,
  configId: string,
  value: string,
): Promise<void> {
  const sess = getSession(sessionId);
  if (!sess) {
    ws.send(JSON.stringify({ type: "error", text: "session not found" }));
    return;
  }

  try {
    const result = await sess.client.setSessionConfigOption(
      sess.acpSessionId,
      configId,
      value,
    );
    ws.send(JSON.stringify({
      type: "config_option_updated",
      sessionId,
      configOptions: result,
    }));
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    ws.send(JSON.stringify({ type: "error", text: `set_config failed: ${msg}` }));
  }
}
