import { spawn } from "node:child_process";
import { getSession, killTerminalProcesses } from "../session.mjs";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs } from "../discovery/agents.mjs";
const PROMPT_TIMEOUT = 15 * 1000; // 15 seconds
const MODEL_ERROR_PATTERNS = [
    /rate limit/i, /quota/i, /429/i, /402/i, /insufficient_quota/i,
    /resource.*exhausted/i, /too many request/i, /billing/i,
    /credit.*exhausted/i, /payment required/i, /model.*not.*found/i,
    /model.*unavailable/i, /api.*error/i, /auth.*error/i,
    /unauthorized/i, /forbidden/i, /403/i, /401/i, /5\d{2}/i,
];
async function ensureSessionAlive(ws, sessionId) {
    const sess = getSession(sessionId);
    if (!sess)
        return false;
    if (sess.acpSessionId && sess.client?.connected)
        return true;
    // ACP connection is dead — restart
    console.log(`[server] ACP connection dead for ${sessionId}, restarting...`);
    killTerminalProcesses(sess);
    try {
        sess.client?.destroy();
    }
    catch { }
    if (sess.process && !sess.process.killed) {
        try {
            (await import("tree-kill")).default(sess.process.pid, "SIGTERM");
        }
        catch { }
    }
    const cwd = sess.cwd || process.cwd();
    const args = getAgentLaunchArgs(sess.agent);
    const proc = spawn(sess.agent, args, {
        cwd,
        env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
        stdio: ["pipe", "pipe", "pipe"],
        shell: true,
    });
    const client = new AcpClient(proc, {
        onSessionUpdate: async (update) => {
            try {
                ws.send(JSON.stringify({ type: "agent_event", sessionId, event: update.update }));
            }
            catch { }
        },
        onPermissionRequest: (params) => {
            return new Promise((resolve) => {
                const requestId = crypto.randomUUID();
                const s = getSession(sessionId);
                if (s)
                    s.pendingPermission = { requestId, resolve };
                try {
                    ws.send(JSON.stringify({ type: "permission_request", sessionId, requestId, toolCall: params.toolCall, options: params.options }));
                }
                catch { }
            });
        },
    });
    proc.stderr.on("data", (chunk) => {
        console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    });
    proc.on("error", () => { });
    proc.on("exit", (code) => {
        console.log(`[server] ${sessionId} restarted process exited with code ${code}`);
    });
    await client.initialize();
    const result = await client.createSession(cwd);
    const acpSessionId = result.sessionId;
    sess.process = proc;
    sess.client = client;
    sess.acpSessionId = acpSessionId;
    sess.pendingPermission = null;
    console.log(`[server] ACP session restarted: ${sessionId} → ${acpSessionId}`);
    return true;
}
export function handleInput(ws, sessionId, text) {
    const sess = getSession(sessionId);
    if (!sess) {
        ws.send(JSON.stringify({ type: "error", text: `session not found: ${sessionId}` }));
        return;
    }
    // Auto-recover if ACP connection is dead
    if (!sess.acpSessionId || !sess.client?.connected) {
        ensureSessionAlive(ws, sessionId).then((ok) => {
            if (!ok) {
                ws.send(JSON.stringify({ type: "error", text: "failed to restart session" }));
                return;
            }
            // Retry prompt on the revived session
            doPrompt(ws, sessionId, text);
        });
        return;
    }
    doPrompt(ws, sessionId, text);
}
function doPrompt(ws, sessionId, text) {
    const sess = getSession(sessionId);
    if (!sess || !sess.acpSessionId)
        return;
    console.log(`[server] calling ACP prompt (acpSessionId=${sess.acpSessionId}, text="${text.slice(0, 50)}")`);
    const startTime = Date.now();
    let timedOut = false;
    let errorDetected = false;
    let stderrHandler = null;
    if (sess.process?.stderr) {
        stderrHandler = (chunk) => {
            if (errorDetected || timedOut)
                return;
            const stderrText = chunk.toString();
            for (const pattern of MODEL_ERROR_PATTERNS) {
                if (pattern.test(stderrText)) {
                    errorDetected = true;
                    console.log(`[server] model error detected: ${stderrText.slice(0, 200)}`);
                    sess.client.cancel(sess.acpSessionId).catch(() => { });
                    sess.client.destroy();
                    ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
                    ws.send(JSON.stringify({ type: "error", sessionId, text: `Model error: ${stderrText.slice(0, 300).trim()}` }));
                    break;
                }
            }
        };
        sess.process.stderr.on("data", stderrHandler);
    }
    const timer = setTimeout(() => {
        if (errorDetected)
            return;
        timedOut = true;
        console.log(`[server] prompt TIMEOUT after ${Date.now() - startTime}ms for ${sessionId}`);
        if (stderrHandler && sess.process?.stderr) {
            try {
                sess.process.stderr.removeListener("data", stderrHandler);
            }
            catch { }
        }
        sess.client.cancel(sess.acpSessionId).catch(() => { });
        sess.client.destroy();
        ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "timeout" }));
        ws.send(JSON.stringify({ type: "error", sessionId, text: `[Timeout] No response in 15s. Switch model and try again.` }));
    }, PROMPT_TIMEOUT);
    sess.client.prompt(sess.acpSessionId, text)
        .then((result) => {
        if (timedOut || errorDetected)
            return;
        clearTimeout(timer);
        if (stderrHandler && sess.process?.stderr) {
            try {
                sess.process.stderr.removeListener("data", stderrHandler);
            }
            catch { }
        }
        console.log(`[server] turn ended after ${Math.floor((Date.now() - startTime) / 1000)}s: ${result?.stopReason}`);
        ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: result?.stopReason }));
    })
        .catch((err) => {
        if (timedOut || errorDetected)
            return;
        clearTimeout(timer);
        if (stderrHandler && sess.process?.stderr) {
            try {
                sess.process.stderr.removeListener("data", stderrHandler);
            }
            catch { }
        }
        const msg = err?.message || String(err);
        console.log(`[server] prompt error after ${Math.floor((Date.now() - startTime) / 1000)}s: ${msg}`);
        ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
        ws.send(JSON.stringify({ type: "error", sessionId, text: msg.includes("closed") || msg.includes("abort")
                ? `[Session expired] Send a message to auto-restart.` : `Agent error: ${msg}` }));
    });
}
//# sourceMappingURL=input.mjs.map