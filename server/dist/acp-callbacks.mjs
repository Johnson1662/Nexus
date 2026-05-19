import path from "node:path";
import fs from "node:fs/promises";
import { spawn } from "node:child_process";
import kill from "tree-kill";
import { getSession } from "./session.mjs";
export function isPathWithinCwd(target, cwd) {
    const resolved = path.resolve(target);
    const relative = path.relative(cwd, resolved);
    return !relative.startsWith("..") && !path.isAbsolute(relative);
}
export function createAcpCallbacks(config) {
    const { ws, sessionId, cwd } = config;
    const onReadTextFile = async (params) => {
        const currentSess = getSession(sessionId);
        if (!currentSess)
            throw new Error("session not found");
        if (!isPathWithinCwd(params.path, cwd)) {
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
    };
    const onWriteTextFile = async (params) => {
        const currentSess = getSession(sessionId);
        if (!currentSess)
            throw new Error("session not found");
        if (!isPathWithinCwd(params.path, cwd)) {
            throw new Error(`path not allowed: ${params.path}`);
        }
        await fs.mkdir(path.dirname(params.path), { recursive: true });
        await fs.writeFile(params.path, params.content, "utf-8");
        return {};
    };
    const onCreateTerminal = async (params) => {
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
            cwd: params.cwd ?? cwd,
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
    };
    const onTerminalOutput = async (params) => {
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
    };
    const onWaitForTerminalExit = async (params) => {
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
    };
    const onKillTerminal = async (params) => {
        const currentSess = getSession(sessionId);
        if (!currentSess)
            throw new Error("session not found");
        const term = currentSess.terminals.get(params.terminalId);
        if (!term)
            throw new Error(`terminal not found: ${params.terminalId}`);
        if (!term.process.killed) {
            try {
                kill(term.process.pid, "SIGTERM");
            }
            catch { }
        }
        return {};
    };
    const onReleaseTerminal = async (params) => {
        const currentSess = getSession(sessionId);
        if (!currentSess)
            throw new Error("session not found");
        const term = currentSess.terminals.get(params.terminalId);
        if (!term)
            throw new Error(`terminal not found: ${params.terminalId}`);
        if (!term.process.killed) {
            try {
                kill(term.process.pid, "SIGTERM");
            }
            catch { }
        }
        currentSess.terminals.delete(params.terminalId);
        return {};
    };
    return {
        onReadTextFile,
        onWriteTextFile,
        onCreateTerminal,
        onTerminalOutput,
        onWaitForTerminalExit,
        onKillTerminal,
        onReleaseTerminal,
    };
}
//# sourceMappingURL=acp-callbacks.mjs.map