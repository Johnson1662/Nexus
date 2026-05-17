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
  ResumeSessionResponse,
  AuthenticateResponse,
  SetSessionModeResponse,
  SetSessionModelResponse,
  SetSessionConfigOptionResponse,
  CloseSessionResponse,
  McpServer,
} from "@agentclientprotocol/sdk";
import type {
  ReadTextFileRequest,
  ReadTextFileResponse,
  WriteTextFileRequest,
  WriteTextFileResponse,
  CreateTerminalRequest,
  CreateTerminalResponse,
  TerminalOutputRequest,
  TerminalOutputResponse,
  WaitForTerminalExitRequest,
  WaitForTerminalExitResponse,
  KillTerminalRequest,
  KillTerminalResponse,
  ReleaseTerminalRequest,
  ReleaseTerminalResponse,
} from "@agentclientprotocol/sdk";
import { type ChildProcess } from "node:child_process";
import { Writable, Readable } from "node:stream";
import type { McpServerConfig } from "../discovery/mcp-config.mjs";

export interface AcpClientCallbacks {
  onSessionUpdate: (params: SessionNotification) => Promise<void>;
  onPermissionRequest: (
    params: RequestPermissionRequest,
  ) => Promise<RequestPermissionResponse>;
  onReadTextFile?: (
    params: ReadTextFileRequest,
  ) => Promise<ReadTextFileResponse>;
  onWriteTextFile?: (
    params: WriteTextFileRequest,
  ) => Promise<WriteTextFileResponse>;
  onCreateTerminal?: (
    params: CreateTerminalRequest,
  ) => Promise<CreateTerminalResponse>;
  onTerminalOutput?: (
    params: TerminalOutputRequest,
  ) => Promise<TerminalOutputResponse>;
  onWaitForTerminalExit?: (
    params: WaitForTerminalExitRequest,
  ) => Promise<WaitForTerminalExitResponse>;
  onKillTerminal?: (
    params: KillTerminalRequest,
  ) => Promise<KillTerminalResponse | void>;
  onReleaseTerminal?: (
    params: ReleaseTerminalRequest,
  ) => Promise<ReleaseTerminalResponse | void>;
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
  public cwd: string = "";

  constructor(proc: ChildProcess, callbacks: AcpClientCallbacks) {
    const input = Writable.toWeb(proc.stdin!) as WritableStream<Uint8Array>;
    const output = Readable.toWeb(proc.stdout!) as ReadableStream<Uint8Array>;
    const stream = ndJsonStream(input, output);

    const client = {
      requestPermission: (params: RequestPermissionRequest) => {
        console.log(`[acp] agent→bridge: requestPermission toolCallId=${params.toolCall?.toolCallId}`);
        return callbacks.onPermissionRequest(params);
      },
      sessionUpdate: (params: SessionNotification) => {
        console.log(`[acp] agent→bridge: sessionUpdate type=${params.update?.sessionUpdate} id=${params.sessionId?.slice(0, 20)}`);
        return callbacks.onSessionUpdate(params);
      },
      readTextFile: callbacks.onReadTextFile
        ? (params: ReadTextFileRequest) => {
            console.log(`[acp] agent→bridge: readTextFile path="${params.path}"`);
            return callbacks.onReadTextFile!(params);
          }
        : undefined,
      writeTextFile: callbacks.onWriteTextFile
        ? (params: WriteTextFileRequest) => {
            console.log(`[acp] agent→bridge: writeTextFile path="${params.path}"`);
            return callbacks.onWriteTextFile!(params);
          }
        : undefined,
      createTerminal: callbacks.onCreateTerminal
        ? (params: CreateTerminalRequest) => {
            console.log(`[acp] agent→bridge: createTerminal command="${params.command}"`);
            return callbacks.onCreateTerminal!(params);
          }
        : undefined,
      terminalOutput: callbacks.onTerminalOutput
        ? (params: TerminalOutputRequest) => {
            console.log(`[acp] agent→bridge: terminalOutput terminalId="${params.terminalId}"`);
            return callbacks.onTerminalOutput!(params);
          }
        : undefined,
      waitForTerminalExit: callbacks.onWaitForTerminalExit
        ? (params: WaitForTerminalExitRequest) => {
            console.log(`[acp] agent→bridge: waitForTerminalExit terminalId="${params.terminalId}"`);
            return callbacks.onWaitForTerminalExit!(params);
          }
        : undefined,
      killTerminal: callbacks.onKillTerminal
        ? (params: KillTerminalRequest) => {
            console.log(`[acp] agent→bridge: killTerminal terminalId="${params.terminalId}"`);
            return callbacks.onKillTerminal!(params);
          }
        : undefined,
      releaseTerminal: callbacks.onReleaseTerminal
        ? (params: ReleaseTerminalRequest) => {
            console.log(`[acp] agent→bridge: releaseTerminal terminalId="${params.terminalId}"`);
            return callbacks.onReleaseTerminal!(params);
          }
        : undefined,
    };

    this.conn = new ClientSideConnection(() => client, stream);
  }

  async initialize(): Promise<InitializeResponse> {
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

  async createSession(
    cwd: string,
    mcpServers?: McpServerConfig[],
  ): Promise<NewSessionResponse> {
    this.cwd = cwd;
    console.log(`[acp] bridge→agent: newSession cwd="${cwd}"`);
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
    this.cwd = cwd;
    console.log(`[acp] bridge→agent: loadSession id="${sessionId.slice(0, 20)}"`);
    return await this.conn.loadSession({
      sessionId,
      cwd,
      mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
    });
  }

  async resumeSession(
    sessionId: string,
    cwd: string,
    mcpServers?: McpServerConfig[],
  ): Promise<ResumeSessionResponse> {
    this.cwd = cwd;
    console.log(`[acp] bridge→agent: resumeSession id="${sessionId.slice(0, 20)}"`);
    return await this.conn.resumeSession({
      sessionId,
      cwd,
      mcpServers: mcpServers ? toMcpServers(mcpServers) : [],
    });
  }

  async prompt(
    sessionId: string,
    text: string,
  ): Promise<PromptResponse> {
    console.log(`[acp] bridge→agent: prompt sessionId="${sessionId.slice(0, 20)}" text="${text.slice(0, 50)}"`);
    return await this.conn.prompt({
      sessionId,
      prompt: [{ type: "text", text }],
    });
  }

  async cancel(sessionId: string): Promise<void> {
    console.log(`[acp] bridge→agent: cancel sessionId="${sessionId.slice(0, 20)}"`);
    await this.conn.cancel({ sessionId });
  }

  async closeSession(sessionId: string): Promise<CloseSessionResponse> {
    console.log(`[acp] bridge→agent: closeSession sessionId="${sessionId.slice(0, 20)}"`);
    return await this.conn.closeSession({ sessionId });
  }

  async authenticate(
    methodId: string,
  ): Promise<AuthenticateResponse | void> {
    console.log(`[acp] bridge→agent: authenticate methodId="${methodId}"`);
    return await this.conn.authenticate({ methodId });
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

  get connected(): boolean {
    try {
      return !(this.conn as any).signal?.aborted;
    } catch {
      return false;
    }
  }

  destroy(): void {
    try {
      (this.conn as any).connection?.close();
    } catch {}
  }
}
