import {
  ClientSideConnection,
  ndJsonStream,
  PROTOCOL_VERSION,
} from "@agentclientprotocol/sdk";
import type {
  InitializeResponse,
  NewSessionResponse,
  PromptResponse,
  SessionNotification,
  RequestPermissionRequest,
  RequestPermissionResponse,
  ListSessionsResponse,
  LoadSessionResponse,
  SetSessionModeResponse,
  SetSessionModelResponse,
  SetSessionConfigOptionResponse,
  McpServer,
} from "@agentclientprotocol/sdk";
import { type ChildProcess } from "node:child_process";
import { Writable, Readable } from "node:stream";
import type { McpServerConfig } from "../discovery/mcp-config.mjs";

export interface AcpClientCallbacks {
  onSessionUpdate: (params: SessionNotification) => Promise<void>;
  onPermissionRequest: (
    params: RequestPermissionRequest,
  ) => Promise<RequestPermissionResponse>;
}

function toMcpServers(configs: McpServerConfig[]): McpServer[] {
  return configs.map((c) => {
    if (c.type === "http" || c.type === "sse") {
      return {
        name: c.name,
        type: c.type,
        url: c.url ?? "",
        headers: c.headers ?? [],
      } as McpServer;
    }
    return {
      name: c.name,
      command: c.command ?? "",
      args: c.args ?? [],
      env: c.env ?? [],
    } as McpServer;
  });
}

export class AcpClient {
  private conn: ClientSideConnection;
  public agentInfo: { name: string; version?: string } | null = null;

  constructor(proc: ChildProcess, callbacks: AcpClientCallbacks) {
    const input = Writable.toWeb(proc.stdin!) as WritableStream<Uint8Array>;
    const output = Readable.toWeb(proc.stdout!) as ReadableStream<Uint8Array>;
    const stream = ndJsonStream(input, output);

    const client = {
      requestPermission: (params: RequestPermissionRequest) =>
        callbacks.onPermissionRequest(params),
      sessionUpdate: (params: SessionNotification) =>
        callbacks.onSessionUpdate(params),
    };

    this.conn = new ClientSideConnection(() => client, stream);
  }

  async initialize(): Promise<InitializeResponse> {
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

  async createSession(
    cwd: string,
    mcpServers?: McpServerConfig[],
  ): Promise<NewSessionResponse> {
    return await this.conn.newSession({
      cwd,
      mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
    });
  }

  async loadSession(
    sessionId: string,
    cwd: string,
    mcpServers?: McpServerConfig[],
  ): Promise<LoadSessionResponse> {
    return await this.conn.loadSession({
      sessionId,
      cwd,
      mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
    });
  }

  async prompt(
    sessionId: string,
    text: string,
  ): Promise<PromptResponse> {
    return await this.conn.prompt({
      sessionId,
      prompt: [{ type: "text", text }],
    });
  }

  async cancel(sessionId: string): Promise<void> {
    await this.conn.cancel({ sessionId });
  }

  async setSessionMode(
    sessionId: string,
    modeId: string,
  ): Promise<SetSessionModeResponse | void> {
    return await this.conn.setSessionMode({ sessionId, modeId });
  }

  async setSessionModel(
    sessionId: string,
    modelId: string,
  ): Promise<SetSessionModelResponse | void> {
    return await this.conn.unstable_setSessionModel({ sessionId, modelId });
  }

  async setSessionConfigOption(
    sessionId: string,
    configId: string,
    value: string,
  ): Promise<SetSessionConfigOptionResponse> {
    return await this.conn.setSessionConfigOption({
      sessionId,
      configId,
      value,
    });
  }

  async listSessions(cwd?: string): Promise<ListSessionsResponse> {
    return await this.conn.listSessions({ cwd: cwd || undefined });
  }

  get closed(): Promise<void> {
    return this.conn.closed;
  }

  destroy(): void {
    try {
      (this.conn as any).connection?.close();
    } catch {}
  }
}
