import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";
import fs from "node:fs/promises";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs } from "../discovery/agents.mjs";
import { setSession, deleteSession, getSession, killSessionProcess, killOldWsSessions, } from "../session.mjs";
function isPathWithinCwd(target, cwd) {
    const resolved = path.resolve(target);
    const relative = path.relative(cwd, resolved);
    return !relative.startsWith("..") && !path.isAbsolute(relative);
}
export async function handleStart(ws, params) {
    const { agent = "opencode", prompt, cwd, model } = params;
    console.log(`[server] starting agent: ${agent}`);
    killOldWsSessions(ws);
    const args = getAgentLaunchArgs(agent);
    const proc = spawn(agent, args, {
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
        cwd: cwd || process.cwd(),
        pendingPermission: null,
        terminals: new Map(),
    };
    const client = new AcpClient(proc, {
        onSessionUpdate: async (update) => {
            const type = update.update?.sessionUpdate || "unknown";
            console.log(`[server] agent_event type=${type} sessionId=${sessionId?.slice(0, 20)}`);
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
        onReadTextFile: async (params) => {
            const currentSess = getSession(sessionId);
            if (!currentSess)
                throw new Error("session not found");
            const effectiveCwd = (client.cwd || cwd) || process.cwd();
            if (!isPathWithinCwd(params.path, effectiveCwd)) {
                throw new Error(`path not allowed: ${params.path}`);
            }
            let content;
            if (params.line != null && params.line > 0) {
                const allLines = (await fs.readFile(params.path, "utf-8")).split("\n");
                const start = params.line - 1;
                const end = params.limit != null ? start + params.limit : undefined;
                content = allLines.slice(start, end).join("\n");
            }
            else {
                content = await fs.readFile(params.path, "utf-8");
                if (params.limit) {
                    content = content.split("\n").slice(0, params.limit).join("\n");
                }
            }
            return { content };
        },
        onWriteTextFile: async (params) => {
            const currentSess = getSession(sessionId);
            if (!currentSess)
                throw new Error("session not found");
            const effectiveCwd = (client.cwd || cwd) || process.cwd();
            if (!isPathWithinCwd(params.path, effectiveCwd)) {
                throw new Error(`path not allowed: ${params.path}`);
            }
            await fs.mkdir(path.dirname(params.path), { recursive: true });
            await fs.writeFile(params.path, params.content, "utf-8");
            return {};
        },
        onCreateTerminal: async (params) => {
            const currentSess = getSession(sessionId);
            if (!currentSess)
                throw new Error("session not found");
            const terminalId = `term-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
            const outputByteLimit = params.outputByteLimit ?? 100000;
            let resolveExit = null;
            const exitPromise = new Promise((resolve) => {
                resolveExit = resolve;
            });
            const terminal = {
                id: terminalId,
                process: null,
                output: "",
                truncated: false,
                exitStatus: null,
                exitPromise,
                resolveExit,
                outputByteLimit,
            };
            currentSess.terminals.set(terminalId, terminal);
            const termProc = spawn(params.command, params.args ?? [], {
                cwd: params.cwd ?? (client.cwd || process.cwd()),
                env: params.env
                    ? { ...process.env, ...Object.fromEntries(params.env.map((e) => [e.name, e.value])) }
                    : { ...process.env },
                stdio: ["pipe", "pipe", "pipe"],
                shell: true,
            });
            terminal.process = termProc;
            termProc.stdout.on("data", (chunk) => {
                const sess = getSession(sessionId);
                const t = sess?.terminals.get(terminalId);
                if (!t || t.truncated)
                    return;
                t.output += chunk.toString();
                if (t.output.length > t.outputByteLimit) {
                    t.output = t.output.slice(t.output.length - t.outputByteLimit);
                    t.truncated = true;
                }
            });
            termProc.stderr.on("data", (chunk) => {
                const sess = getSession(sessionId);
                const t = sess?.terminals.get(terminalId);
                if (!t || t.truncated)
                    return;
                t.output += chunk.toString();
                if (t.output.length > t.outputByteLimit) {
                    t.output = t.output.slice(t.output.length - t.outputByteLimit);
                    t.truncated = true;
                }
            });
            termProc.on("exit", (code, sig) => {
                const sess = getSession(sessionId);
                const t = sess?.terminals.get(terminalId);
                if (t) {
                    t.exitStatus = { exitCode: code, signal: sig ?? null };
                    if (t.resolveExit)
                        t.resolveExit();
                }
            });
            termProc.on("error", () => {
                const sess = getSession(sessionId);
                const t = sess?.terminals.get(terminalId);
                if (t) {
                    t.exitStatus = { exitCode: -1, signal: null };
                    if (t.resolveExit)
                        t.resolveExit();
                }
            });
            return { terminalId };
        },
        onTerminalOutput: async (params) => {
            const currentSess = getSession(sessionId);
            if (!currentSess)
                throw new Error("session not found");
            const term = currentSess.terminals.get(params.terminalId);
            if (!term)
                throw new Error(`terminal not found: ${params.terminalId}`);
            return {
                output: term.output,
                truncated: term.truncated,
                exitStatus: term.exitStatus ?? undefined,
            };
        },
        onWaitForTerminalExit: async (params) => {
            const currentSess = getSession(sessionId);
            if (!currentSess)
                throw new Error("session not found");
            const term = currentSess.terminals.get(params.terminalId);
            if (!term)
                throw new Error(`terminal not found: ${params.terminalId}`);
            await term.exitPromise;
            return {
                exitCode: term.exitStatus?.exitCode ?? null,
                signal: term.exitStatus?.signal ?? null,
            };
        },
        onKillTerminal: async (params) => {
            const currentSess = getSession(sessionId);
            if (!currentSess)
                throw new Error("session not found");
            const term = currentSess.terminals.get(params.terminalId);
            if (!term)
                throw new Error(`terminal not found: ${params.terminalId}`);
            if (!term.process.killed) {
                try {
                    const { default: kill } = await import("tree-kill");
                    kill(term.process.pid, "SIGTERM");
                }
                catch { }
            }
            return {};
        },
        onReleaseTerminal: async (params) => {
            const currentSess = getSession(sessionId);
            if (!currentSess)
                throw new Error("session not found");
            const term = currentSess.terminals.get(params.terminalId);
            if (!term)
                throw new Error(`terminal not found: ${params.terminalId}`);
            if (!term.process.killed) {
                try {
                    const { default: kill } = await import("tree-kill");
                    kill(term.process.pid, "SIGTERM");
                }
                catch { }
            }
            currentSess.terminals.delete(params.terminalId);
            return {};
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
        if (sessionResult.models) {
            console.log(`[server] default model: ${sessionResult.models.currentModelId || "not set"}`);
        }
        if (sessionResult.configOptions) {
            const modelOpt = sessionResult.configOptions.find((o) => o.id === "model" || o.category === "model");
            if (modelOpt)
                console.log(`[server] agent default model: ${modelOpt.currentValue}`);
        }
        if (model) {
            console.log(`[server] setting model to ${model}`);
            await client.setSessionModel(acpSessionId, model);
        }
        try {
            const sessionTitle = prompt ? prompt.slice(0, 50) + (prompt.length > 50 ? "\u2026" : "") : "New Session";
            ws.send(JSON.stringify({
                type: "session_started",
                sessionId,
                agent,
                prompt,
                acpSessionId,
                ...(model ? { model } : {}),
                title: sessionTitle,
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