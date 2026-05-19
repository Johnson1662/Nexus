import type { WebSocket } from "ws";
import type { AcpClient } from "../acp/client.mjs";
import { findSessionForWs } from "../session.mjs";
import { createTempClient } from "../temp-client.mjs";

export async function handleListModels(
  ws: WebSocket,
  agent?: string,
): Promise<void> {
  const sess = findSessionForWs(ws);

  // Use existing bridge session's client if alive
  if (sess && sess.client?.connected) {
    await doListModels(ws, sess.client, sess.cwd || process.cwd());
    return;
  }

  // Fall back to temporary ACP client
  if (!agent) {
    ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
    return;
  }

  console.log(`[server] list_models: creating temp client for agent="${agent}"`);
  let temp: { client: AcpClient; destroy: () => void } | null = null;
  try {
    temp = await createTempClient(agent);
    await doListModels(ws, temp.client, temp.client.cwd || process.cwd());
  } catch (err: any) {
    console.log(`[server] list_models (temp) error: ${err.message}`);
    ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
  } finally {
    if (temp) temp.destroy();
  }
}

async function doListModels(
  ws: WebSocket,
  client: AcpClient,
  cwd: string,
): Promise<void> {
  const acpResult = await client.createSession(cwd);
  const acpSessionId = (acpResult as any).sessionId;
  const models = (acpResult as any).models?.availableModels || [];
  const modes = (acpResult as any).modes?.availableModes || [];
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
  // Close the temporary ACP session to avoid orphans
  if (acpSessionId) {
    client.closeSession(acpSessionId).catch((err: Error) => {
      console.log(`[server] failed to close temp list_models session: ${err.message}`);
    });
  }
  ws.send(
    JSON.stringify({
      type: "model_list",
      models: mappedModels,
      modes: mappedModes,
    }),
  );
}
