import type { WebSocket } from "ws";
import { findSessionForWs } from "../session.mjs";

export async function handleListModels(
  ws: WebSocket,
): Promise<void> {
  const sess = findSessionForWs(ws);
  if (!sess) {
    ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
    return;
  }

  try {
    const result = await sess.client.createSession(sess.cwd || process.cwd());
    const models = (result as any).models?.availableModels || [];
    const modes = (result as any).modes?.availableModes || [];
    const mappedModels = models.map((m: any) => ({
      modelId: m.modelId,
      name: m.name,
    }));
    const mappedModes = modes.map((m: any) => ({
      value: m.id,
      name: m.name,
    }));
    console.log(
      `[server] list_models: ${mappedModels.length} models, ${mappedModes.length} modes`,
    );
    ws.send(
      JSON.stringify({
        type: "model_list",
        models: mappedModels,
        modes: mappedModes,
      }),
    );
  } catch (err: any) {
    console.log(`[server] list_models error: ${err.message}`);
    ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
  }
}
