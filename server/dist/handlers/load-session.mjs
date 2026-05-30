import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs, isValidAgent } from "../discovery/agents.mjs";
import { setSession, deleteSession, getSession, killSessionProcess, cleanupWsSessions, trimToolCallIds, bufferAgentEvent, } from "../session.mjs";
import { createAcpCallbacks } from "../acp-callbacks.mjs";
export async function handleLoadSession(ws, params) {
    const { sessionId: targetSessionId, cwd, agent = "opencode", model } = params;
    if (!targetSessionId) {
        ws.send(JSON.stringify({ type: "error", text: "sessionId is required" }));
        return;
    }
    if (!isValidAgent(agent)) {
        ws.send(JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }));
        return;
    }
    cleanupWsSessions(ws);
    const args = getAgentLaunchArgs(agent);
    const proc = spawn(agent, args, {
        cwd: cwd || process.cwd(),
        env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
        stdio: ["pipe", "pipe", "pipe"],
        shell: true,
    });
    const bridgeSessionId = `acp-${Date.now()}-${randomUUID().slice(0, 8)}`;
    const sess = {
        ws,
        sessionId: bridgeSessionId,
        process: proc,
        agent,
        cwd: cwd || process.cwd(),
        pendingPermission: null,
        terminals: new Map(),
        toolCallIdMap: new Map(),
        orphanedAt: null,
        messageBuffer: [],
    };
    const client = new AcpClient(proc, {
        onSessionUpdate: async (update) => {
            const toolCallEvt = update.update;
            if (toolCallEvt?.sessionUpdate === "tool_call" && toolCallEvt?.toolCallId) {
                const s = getSession(bridgeSessionId);
                if (s) {
                    const rawId = String(toolCallEvt.toolCallId);
                    const locations = (toolCallEvt.locations || []);
                    const rawInput = toolCallEvt.rawInput;
                    for (const loc of locations) {
                        if (loc.path) {
                            const rp = path.resolve(loc.path);
                            s.toolCallIdMap.set(`read:${rp}`, rawId);
                            s.toolCallIdMap.set(`write:${rp}`, rawId);
                        }
                    }
                    if (locations.length === 0 && rawInput && typeof rawInput.path === "string") {
                        const rp = path.resolve(rawInput.path);
                        if (toolCallEvt.kind === "read") {
                            s.toolCallIdMap.set(`read:${rp}`, rawId);
                        }
                        else if (toolCallEvt.kind === "edit") {
                            s.toolCallIdMap.set(`write:${rp}`, rawId);
                        }
                        else {
                            s.toolCallIdMap.set(`read:${rp}`, rawId);
                            s.toolCallIdMap.set(`write:${rp}`, rawId);
                        }
                    }
                    s.lastToolCallId = rawId;
                    trimToolCallIds(s);
                }
            }
            try {
                const eventPayload = {
                    type: "agent_event",
                    sessionId: bridgeSessionId,
                    event: update.update,
                };
                sess.ws?.send(JSON.stringify(eventPayload));
                bufferAgentEvent(bridgeSessionId, eventPayload);
            }
            catch { }
        },
        onPermissionRequest: (params) => {
            return new Promise((resolve) => {
                const requestId = randomUUID();
                const currentSess = getSession(bridgeSessionId);
                if (currentSess) {
                    currentSess.pendingPermission = { requestId, resolve };
                }
                try {
                    sess.ws?.send(JSON.stringify({
                        type: "permission_request",
                        sessionId: bridgeSessionId,
                        requestId,
                        toolCall: params.toolCall,
                        options: params.options,
                    }));
                }
                catch { }
            });
        },
        ...createAcpCallbacks({ sessionId: bridgeSessionId, cwd: cwd || process.cwd(), toolCallIdMap: sess.toolCallIdMap }),
    });
    sess.client = client;
    sess.loadedSessionId = targetSessionId;
    setSession(bridgeSessionId, sess);
    proc.stderr.on("data", (chunk) => {
        console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
        try {
            sess.ws?.send(JSON.stringify({
                type: "agent_stderr",
                sessionId: bridgeSessionId,
                text: chunk.toString(),
            }));
        }
        catch { }
    });
    proc.on("error", (err) => {
        console.log(`[server] ${bridgeSessionId} spawn error: ${err.message}`);
        deleteSession(bridgeSessionId);
    });
    proc.on("exit", (code) => {
        console.log(`[server] ${bridgeSessionId} exited with code ${code}`);
        deleteSession(bridgeSessionId);
    });
    try {
        console.log(`[server] initializing ACP for load session ${targetSessionId}...`);
        await client.initialize();
        console.log(`[server] loading session ${targetSessionId}`);
        const loadResult = await client.loadSession(targetSessionId, cwd || process.cwd());
        sess.acpSessionId = targetSessionId;
        const models = loadResult.models?.availableModels || [];
        const modes = loadResult.modes?.availableModes || [];
        if (models.length > 0 || modes.length > 0) {
            const mappedModels = models.map((m) => ({ modelId: m.modelId, name: m.name }));
            const mappedModes = modes.map((m) => ({ value: m.id, name: m.name }));
            sess.ws?.send(JSON.stringify({ type: "model_list", models: mappedModels, modes: mappedModes }));
        }
        if (model) {
            await client.setSessionModel(targetSessionId, model).catch(() => { });
        }
        sess.ws?.send(JSON.stringify({
            type: "session_started",
            sessionId: bridgeSessionId,
            agent,
            loadedSessionId: targetSessionId,
            ...(model ? { model } : {}),
        }));
    }
    catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.log(`[server] load_session error: ${msg}`);
        sess.ws?.send(JSON.stringify({
            type: "error",
            text: `load session failed: ${msg}`,
        }));
        killSessionProcess(sess);
        deleteSession(bridgeSessionId);
    }
}
//# sourceMappingURL=load-session.mjs.map