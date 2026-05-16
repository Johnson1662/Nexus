import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { AcpClient } from "../acp/client.mjs";
import { setSession, deleteSession, getSession, killSessionProcess, killOldWsSessions, } from "../session.mjs";
const DEFAULT_MODEL = "opencode/minimax-m2.5-free";
export async function handleStart(ws, params) {
    const { agent = "opencode", prompt, cwd, model } = params;
    const effectiveModel = model || DEFAULT_MODEL;
    console.log(`[server] starting agent: ${agent}`);
    killOldWsSessions(ws);
    const proc = spawn(agent, ["acp"], {
        cwd: cwd || process.cwd(),
        env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
        stdio: ["pipe", "pipe", "pipe"],
        shell: true,
    });
    const sessionId = `acp-${Date.now()}`;
    const sess = {
        ws,
        sessionId,
        process: proc,
        agent,
        pendingPermission: null,
    };
    const client = new AcpClient(proc, {
        onSessionUpdate: async (update) => {
            try {
                ws.send(JSON.stringify({
                    type: "agent_event",
                    sessionId,
                    event: update.update,
                }));
            }
            catch { }
        },
        onPermissionRequest: (params) => {
            return new Promise((resolve) => {
                const requestId = randomUUID();
                const currentSess = getSession(sessionId);
                if (currentSess) {
                    currentSess.pendingPermission = { requestId, resolve };
                }
                try {
                    ws.send(JSON.stringify({
                        type: "permission_request",
                        sessionId,
                        requestId,
                        toolCall: params.toolCall,
                        options: params.options,
                    }));
                }
                catch { }
            });
        },
    });
    sess.client = client;
    setSession(sessionId, sess);
    proc.stderr.on("data", (chunk) => {
        const text = chunk.toString();
        console.log(`[server] stderr: ${text.slice(0, 200)}`);
        try {
            ws.send(JSON.stringify({ type: "agent_stderr", sessionId, text }));
        }
        catch { }
    });
    proc.on("error", (err) => {
        console.log(`[server] ${sessionId} spawn error: ${err.message}`);
        try {
            ws.send(JSON.stringify({ type: "error", text: `spawn failed: ${err.message}` }));
        }
        catch { }
        deleteSession(sessionId);
    });
    proc.on("exit", (code) => {
        console.log(`[server] ${sessionId} exited with code ${code}`);
        try {
            ws.send(JSON.stringify({ type: "session_ended", sessionId, exitCode: code }));
        }
        catch { }
        deleteSession(sessionId);
    });
    try {
        console.log(`[server] initializing ACP for ${sessionId}...`);
        const initResult = await client.initialize();
        console.log(`[server] ACP initialized, agent: ${initResult?.agentInfo?.name}`);
        console.log(`[server] creating session for ${sessionId}...`);
        const sessionResult = await client.createSession(cwd || process.cwd());
        const acpSessionId = sessionResult.sessionId;
        sess.acpSessionId = acpSessionId;
        console.log(`[server] ACP session created: ${acpSessionId}`);
        console.log(`[server] setting model to ${effectiveModel}`);
        await client.setSessionModel(acpSessionId, effectiveModel);
        try {
            ws.send(JSON.stringify({
                type: "session_started",
                sessionId,
                agent,
                prompt,
                acpSessionId,
                model: effectiveModel,
            }));
        }
        catch { }
        if (prompt) {
            client.prompt(acpSessionId, prompt).then((result) => {
                console.log(`[server] turn ended: ${result?.stopReason}`);
                try {
                    ws.send(JSON.stringify({
                        type: "turn_ended",
                        sessionId,
                        stopReason: result?.stopReason,
                    }));
                }
                catch { }
            }, (err) => {
                const msg = err instanceof Error ? err.message : String(err);
                console.log(`[server] prompt error: ${msg}`);
            });
        }
    }
    catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.log(`[server] ACP init error: ${msg}`);
        try {
            ws.send(JSON.stringify({
                type: "error",
                text: `ACP initialization failed: ${msg}`,
            }));
        }
        catch { }
        killSessionProcess(sess);
        deleteSession(sessionId);
    }
}
//# sourceMappingURL=start.mjs.map