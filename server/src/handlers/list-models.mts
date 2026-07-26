import type { WebSocket } from "ws";
import { sessionManager } from "../session-manager.mjs";
import { isValidAgent } from "../discovery/agents.mjs";
import { agentRegistry } from "../agent-registry-service.mjs";

export async function handleListModels(
  ws: WebSocket,
  agent?: string,
  refresh: boolean = false,
): Promise<void> {
  const sess = sessionManager.findSessionForWs(ws);
  const targetAgent = agent || sess?.agent || "";

  if (!targetAgent) {
    ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
    return;
  }

  if (agent && !isValidAgent(agent)) {
    ws.send(JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }));
    return;
  }

  try {
    const cwd = sess?.cwd || process.cwd();
    const existingClient =
      sess?.client?.connected && sess.agent === targetAgent
        ? sess.client
        : undefined;
    const list = await agentRegistry.listModels(
      targetAgent,
      cwd,
      refresh,
      existingClient,
    );
    ws.send(
      JSON.stringify({ type: "model_list", models: list.models, modes: list.modes }),
    );
  } catch (err: any) {
    console.log(`[server] list_models error: ${err.message}`);
    ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
  }
}
