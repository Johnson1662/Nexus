import type { WebSocket } from "ws";
import type { AcpClient } from "../acp/client.mjs";
import { findSessionForWs } from "../session.mjs";
import { createTempClient } from "../temp-client.mjs";
import { isValidAgent } from "../discovery/agents.mjs";
import { extractModelList, queryModelListOnce, type ModelList } from "../model-list.mjs";
import { join } from "node:path";
import { homedir } from "node:os";

export async function handleListModels(
  ws: WebSocket,
  agent?: string,
  refresh: boolean = false,
): Promise<void> {
  const sess = findSessionForWs(ws);

  if (sess && sess.client?.connected) {
    try {
      const list = await queryModelListOnce(
        sess.agent || agent || "opencode",
        sess.cwd || process.cwd(),
        refresh,
        () => doListModels(sess.client, sess.cwd || process.cwd()),
      );
      sendModelList(ws, list);
    } catch (err: any) {
      console.log(`[server] list_models error: ${err.message}`);
      ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
    }
    return;
  }

  if (!agent) {
    ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
    return;
  }

  if (!isValidAgent(agent)) {
    ws.send(JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }));
    return;
  }

  const cwd = join(homedir(), ".anywhere");
  try {
    const list = await queryModelListOnce(agent, cwd, refresh, async () => {
      console.log(`[server] list_models: creating temp client for agent="${agent}"`);
      let temp: { client: AcpClient; destroy: () => void } | null = null;
      try {
        temp = await createTempClient(agent);
        return await doListModels(temp.client, cwd);
      } finally {
        if (temp) temp.destroy();
      }
    });
    sendModelList(ws, list);
  } catch (err: any) {
    console.log(`[server] list_models (temp) error: ${err.message}`);
    ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
  }
}

async function doListModels(
  client: AcpClient,
  cwd: string,
): Promise<ModelList> {
  const acpResult = await client.createSession(cwd);
  const acpSessionId = (acpResult as any).sessionId;
  const list = extractModelList(acpResult);
  console.log(
    `[server] list_models: ${list.models.length} models, ${list.modes.length} modes`,
  );

  if (acpSessionId) {
    client.closeSession(acpSessionId).catch(() => {});
  }
  return list;
}

function sendModelList(ws: WebSocket, list: ModelList): void {
  ws.send(
    JSON.stringify({
      type: "model_list",
      models: list.models,
      modes: list.modes,
    }),
  );
}
