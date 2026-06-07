import { findSessionForWs } from "../session.mjs";
import { createTempClient } from "../temp-client.mjs";
import { isValidAgent } from "../discovery/agents.mjs";
export async function handleListModels(ws, agent) {
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
    if (!isValidAgent(agent)) {
        ws.send(JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }));
        return;
    }
    console.log(`[server] list_models: creating temp client for agent="${agent}"`);
    let temp = null;
    try {
        temp = await createTempClient(agent);
        await doListModels(ws, temp.client, temp.client.cwd || process.cwd());
    }
    catch (err) {
        console.log(`[server] list_models (temp) error: ${err.message}`);
        ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
    }
    finally {
        if (temp)
            temp.destroy();
    }
}
async function doListModels(ws, client, cwd) {
    const acpResult = await client.createSession(cwd);
    const acpSessionId = acpResult.sessionId;
    // OpenCode returns models/modes as configOptions rather than models.availableModels
    const configOptions = acpResult.configOptions || [];
    const modelConfig = configOptions.find((o) => o.category === "model" || o.id === "model");
    const modeConfig = configOptions.find((o) => o.category === "mode" || o.id === "mode");
    const rawModels = modelConfig?.options || [];
    const rawModes = modeConfig?.options || [];
    const mappedModels = rawModels.map((m) => ({
        modelId: m.value || m.modelId,
        name: m.name,
    }));
    const mappedModes = rawModes.map((m) => ({
        value: m.value || m.id,
        name: m.name,
    }));
    console.log(`[server] list_models: ${mappedModels.length} models, ${mappedModes.length} modes`);
    // Close the temporary ACP session to avoid orphans
    if (acpSessionId) {
        client.closeSession(acpSessionId).catch((err) => {
            console.log(`[server] failed to close temp list_models session: ${err.message}`);
        });
    }
    ws.send(JSON.stringify({
        type: "model_list",
        models: mappedModels,
        modes: mappedModes,
    }));
}
