import { findSessionForWs } from "../session.mjs";
export async function handleListModels(ws) {
    const sess = findSessionForWs(ws);
    if (!sess) {
        ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
        return;
    }
    try {
        const result = await sess.client.createSession(process.cwd());
        const models = result.models?.availableModels || [];
        const modes = result.modes?.availableModes || [];
        const mappedModels = models.map((m) => ({
            modelId: m.modelId,
            name: m.name,
        }));
        const mappedModes = modes.map((m) => ({
            value: m.id,
            name: m.name,
        }));
        console.log(`[server] list_models: ${mappedModels.length} models, ${mappedModes.length} modes`);
        ws.send(JSON.stringify({
            type: "model_list",
            models: mappedModels,
            modes: mappedModes,
        }));
    }
    catch (err) {
        console.log(`[server] list_models error: ${err.message}`);
        ws.send(JSON.stringify({ type: "model_list", models: [], modes: [] }));
    }
}
//# sourceMappingURL=list-models.mjs.map