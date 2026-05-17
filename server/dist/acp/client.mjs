import { ClientSideConnection, ndJsonStream, PROTOCOL_VERSION, } from "@agentclientprotocol/sdk";
import { Writable, Readable } from "node:stream";
function toMcpServers(configs) {
    return configs.map((c) => {
        if (c.type === "http" || c.type === "sse") {
            return {
                name: c.name,
                type: c.type,
                url: c.url ?? "",
                headers: c.headers ?? [],
            };
        }
        return {
            name: c.name,
            command: c.command ?? "",
            args: c.args ?? [],
            env: c.env ?? [],
        };
    });
}
export class AcpClient {
    conn;
    agentInfo = null;
    cwd = "";
    constructor(proc, callbacks) {
        const input = Writable.toWeb(proc.stdin);
        const output = Readable.toWeb(proc.stdout);
        const stream = ndJsonStream(input, output);
        const client = {
            requestPermission: (params) => {
                console.log(`[acp] agent→bridge: requestPermission toolCallId=${params.toolCall?.toolCallId}`);
                return callbacks.onPermissionRequest(params);
            },
            sessionUpdate: (params) => {
                console.log(`[acp] agent→bridge: sessionUpdate type=${params.update?.sessionUpdate} id=${params.sessionId?.slice(0, 20)}`);
                return callbacks.onSessionUpdate(params);
            },
            readTextFile: callbacks.onReadTextFile
                ? (params) => {
                    console.log(`[acp] agent→bridge: readTextFile path="${params.path}"`);
                    return callbacks.onReadTextFile(params);
                }
                : undefined,
            writeTextFile: callbacks.onWriteTextFile
                ? (params) => {
                    console.log(`[acp] agent→bridge: writeTextFile path="${params.path}"`);
                    return callbacks.onWriteTextFile(params);
                }
                : undefined,
            createTerminal: callbacks.onCreateTerminal
                ? (params) => {
                    console.log(`[acp] agent→bridge: createTerminal command="${params.command}"`);
                    return callbacks.onCreateTerminal(params);
                }
                : undefined,
            terminalOutput: callbacks.onTerminalOutput
                ? (params) => {
                    console.log(`[acp] agent→bridge: terminalOutput terminalId="${params.terminalId}"`);
                    return callbacks.onTerminalOutput(params);
                }
                : undefined,
            waitForTerminalExit: callbacks.onWaitForTerminalExit
                ? (params) => {
                    console.log(`[acp] agent→bridge: waitForTerminalExit terminalId="${params.terminalId}"`);
                    return callbacks.onWaitForTerminalExit(params);
                }
                : undefined,
            killTerminal: callbacks.onKillTerminal
                ? (params) => {
                    console.log(`[acp] agent→bridge: killTerminal terminalId="${params.terminalId}"`);
                    return callbacks.onKillTerminal(params);
                }
                : undefined,
            releaseTerminal: callbacks.onReleaseTerminal
                ? (params) => {
                    console.log(`[acp] agent→bridge: releaseTerminal terminalId="${params.terminalId}"`);
                    return callbacks.onReleaseTerminal(params);
                }
                : undefined,
        };
        this.conn = new ClientSideConnection(() => client, stream);
    }
    async initialize() {
        console.log(`[acp] bridge→agent: initialize (fs=true, terminal=true)`);
        const result = await this.conn.initialize({
            protocolVersion: PROTOCOL_VERSION,
            clientCapabilities: {
                fs: { readTextFile: true, writeTextFile: true },
                terminal: true,
            },
            clientInfo: {
                name: "anywhere-bridge",
                version: "0.3.0",
            },
        });
        this.agentInfo = result.agentInfo ?? null;
        console.log(`[acp] agent→bridge: initialized agent=${result?.agentInfo?.name} v=${result?.agentInfo?.version}`);
        return result;
    }
    async createSession(cwd, mcpServers) {
        this.cwd = cwd;
        console.log(`[acp] bridge→agent: newSession cwd="${cwd}"`);
        return await this.conn.newSession({
            cwd,
            mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
        });
    }
    async loadSession(sessionId, cwd, mcpServers) {
        this.cwd = cwd;
        console.log(`[acp] bridge→agent: loadSession id="${sessionId.slice(0, 20)}"`);
        return await this.conn.loadSession({
            sessionId,
            cwd,
            mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
        });
    }
    async resumeSession(sessionId, cwd, mcpServers) {
        this.cwd = cwd;
        console.log(`[acp] bridge→agent: resumeSession id="${sessionId.slice(0, 20)}"`);
        return await this.conn.resumeSession({
            sessionId,
            cwd,
            mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
        });
    }
    async prompt(sessionId, text) {
        console.log(`[acp] bridge→agent: prompt sessionId="${sessionId.slice(0, 20)}" text="${text.slice(0, 50)}"`);
        return await this.conn.prompt({
            sessionId,
            prompt: [{ type: "text", text }],
        });
    }
    async cancel(sessionId) {
        console.log(`[acp] bridge→agent: cancel sessionId="${sessionId.slice(0, 20)}"`);
        await this.conn.cancel({ sessionId });
    }
    async closeSession(sessionId) {
        console.log(`[acp] bridge→agent: closeSession sessionId="${sessionId.slice(0, 20)}"`);
        return await this.conn.closeSession({ sessionId });
    }
    async authenticate(methodId) {
        console.log(`[acp] bridge→agent: authenticate methodId="${methodId}"`);
        return await this.conn.authenticate({ methodId });
    }
    async setSessionMode(sessionId, modeId) {
        return await this.conn.setSessionMode({ sessionId, modeId });
    }
    async setSessionModel(sessionId, modelId) {
        return await this.conn.unstable_setSessionModel({ sessionId, modelId });
    }
    async setSessionConfigOption(sessionId, configId, value) {
        return await this.conn.setSessionConfigOption({
            sessionId,
            configId,
            value,
        });
    }
    async listSessions(cwd) {
        return await this.conn.listSessions({ cwd: cwd || undefined });
    }
    get closed() {
        return this.conn.closed;
    }
    get connected() {
        try {
            return !this.conn.signal?.aborted;
        }
        catch {
            return false;
        }
    }
    destroy() {
        try {
            this.conn.connection?.close();
        }
        catch { }
    }
}
//# sourceMappingURL=client.mjs.map