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
    constructor(proc, callbacks) {
        const input = Writable.toWeb(proc.stdin);
        const output = Readable.toWeb(proc.stdout);
        const stream = ndJsonStream(input, output);
        const client = {
            requestPermission: (params) => callbacks.onPermissionRequest(params),
            sessionUpdate: (params) => callbacks.onSessionUpdate(params),
        };
        this.conn = new ClientSideConnection(() => client, stream);
    }
    async initialize() {
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
        return result;
    }
    async createSession(cwd, mcpServers) {
        return await this.conn.newSession({
            cwd,
            mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
        });
    }
    async loadSession(sessionId, cwd, mcpServers) {
        return await this.conn.loadSession({
            sessionId,
            cwd,
            mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
        });
    }
    async prompt(sessionId, text) {
        return await this.conn.prompt({
            sessionId,
            prompt: [{ type: "text", text }],
        });
    }
    async cancel(sessionId) {
        await this.conn.cancel({ sessionId });
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
    destroy() {
        try {
            this.conn.connection?.close();
        }
        catch { }
    }
}
//# sourceMappingURL=client.mjs.map