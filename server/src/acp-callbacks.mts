import path from "node:path";
import fs from "node:fs/promises";
import { realpathSync } from "node:fs";
import { spawn } from "node:child_process";
import kill from "tree-kill";
import type { WebSocket } from "ws";
import { getSession, bufferAgentEvent } from "./session.mjs";
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

export function isPathWithinCwd(target: string, cwd: string): boolean {
  const resolved = path.resolve(target);
  // Resolve symlinks to prevent symlink-based directory escape
  let realResolved: string;
  try {
    realResolved = realpathSync(resolved);
  } catch {
    // File doesn't exist yet (e.g. write operation) — resolve parent dir instead
    const parent = path.dirname(resolved);
    try {
      const realParent = realpathSync(parent);
      realResolved = path.join(realParent, path.basename(resolved));
    } catch {
      return false;
    }
  }
  const realCwd: string = realpathSync(cwd);
  const relative = path.relative(realCwd, realResolved);
  return !relative.startsWith("..") && !path.isAbsolute(relative);
}

interface AcpCallbacksConfig {
  ws?: import("ws").WebSocket;
  sessionId: string;
  cwd: string;
  toolCallIdMap?: Map<string, string>;
}

export function createAcpCallbacks(config: AcpCallbacksConfig): {
  onReadTextFile: (params: ReadTextFileRequest) => Promise<ReadTextFileResponse>;
  onWriteTextFile: (params: WriteTextFileRequest) => Promise<WriteTextFileResponse>;
  onCreateTerminal: (params: CreateTerminalRequest) => Promise<CreateTerminalResponse>;
  onTerminalOutput: (params: TerminalOutputRequest) => Promise<TerminalOutputResponse>;
  onWaitForTerminalExit: (params: WaitForTerminalExitRequest) => Promise<WaitForTerminalExitResponse>;
  onKillTerminal: (params: KillTerminalRequest) => Promise<KillTerminalResponse | void>;
  onReleaseTerminal: (params: ReleaseTerminalRequest) => Promise<ReleaseTerminalResponse | void>;
} {
  const { sessionId, cwd, toolCallIdMap } = config;
  
  // Resolve WS dynamically from session map — supports session reclaim after reconnect
  function getSessionWs(): import("ws").WebSocket | undefined {
    const sess = getSession(sessionId);
    return sess?.ws || undefined;
  }

  function sendToolCallUpdate(toolCallId: string, status: string, content: object[]): void {
    const originalId = toolCallIdMap?.get(toolCallId);
    const effectiveId = originalId || toolCallId;
    try {
      const eventPayload = {
        type: "agent_event",
        sessionId,
        event: {
          sessionUpdate: "tool_call_update",
          toolCallId: effectiveId,
          status,
          toolCallContent: content,
        },
      };
      const wss = getSessionWs();
      bufferAgentEvent(sessionId, eventPayload);
      if (wss) wss.send(JSON.stringify(eventPayload));
    } catch {}
  }

  function fileToolCallId(prefix: string, filePath: string): string {
    return `${prefix}:${path.resolve(filePath)}`;
  }

  const onReadTextFile = async (params: ReadTextFileRequest): Promise<ReadTextFileResponse> => {
    const currentSess = getSession(sessionId);
    if (!currentSess) throw new Error("session not found");
    if (!isPathWithinCwd(params.path, cwd)) {
      throw new Error(`path not allowed: ${params.path}`);
    }
    let content: string;
    if (params.line != null && params.line > 0) {
      const allLines = (await fs.readFile(params.path, "utf-8")).split("\n");
      const start = params.line - 1;
      const end = params.limit != null ? start + params.limit : undefined;
      content = allLines.slice(start, end).join("\n");
    } else {
      content = await fs.readFile(params.path, "utf-8");
      if (params.limit) {
        content = content.split("\n").slice(0, params.limit).join("\n");
      }
    }
    sendToolCallUpdate(fileToolCallId("read", params.path), "completed", [
      {
        type: "content",
        content: {
          type: "text",
          text: content,
        },
      },
    ]);
    return { content };
  };

  const onWriteTextFile = async (params: WriteTextFileRequest): Promise<WriteTextFileResponse> => {
    const currentSess = getSession(sessionId);
    if (!currentSess) throw new Error("session not found");
    if (!isPathWithinCwd(params.path, cwd)) {
      throw new Error(`path not allowed: ${params.path}`);
    }
    let oldText = "";
    try {
      oldText = await fs.readFile(params.path, "utf-8");
    } catch {
      oldText = "";
    }
    await fs.mkdir(path.dirname(params.path), { recursive: true });
    await fs.writeFile(params.path, params.content, "utf-8");
    sendToolCallUpdate(fileToolCallId("write", params.path), "completed", [
      {
        type: "diff",
        path: params.path,
        oldText,
        newText: params.content,
      },
    ]);
    return {};
  };

  const onCreateTerminal = async (params: CreateTerminalRequest): Promise<CreateTerminalResponse> => {
    const currentSess = getSession(sessionId);
    if (!currentSess) throw new Error("session not found");

    const terminalId = `term-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    // Map terminalId to the original toolCallId so tool_call_update can find the original card
    if (currentSess.lastToolCallId) {
      currentSess.toolCallIdMap.set(terminalId, currentSess.lastToolCallId);
    }
    const outputByteLimit = params.outputByteLimit ?? 100000;

    let resolveExit: (() => void) | null = null;
    const exitPromise = new Promise<void>((resolve) => {
      resolveExit = resolve;
    });

    const terminal = {
      id: terminalId,
      process: null as any,
      output: "",
      truncated: false,
      exitStatus: null as { exitCode: number | null; signal: string | null } | null,
      exitPromise,
      resolveExit,
      outputByteLimit,
    };
    currentSess.terminals.set(terminalId, terminal);

    const sendTerminalUpdate = (status: string): void => {
      const sess = getSession(sessionId);
      const t = sess?.terminals.get(terminalId);
      if (!t) return;
      sendToolCallUpdate(terminalId, status, [
        {
          type: "terminal",
          terminalId,
          content: {
            type: "text",
            text: t.output,
          },
        },
      ]);
    };

    const termProc = spawn(params.command, params.args ?? [], {
      cwd: params.cwd ?? cwd,
      env: params.env
        ? { ...process.env, ...Object.fromEntries(params.env.map((e: { name: string; value: string }) => [e.name, e.value])) }
        : { ...process.env },
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
    });

    terminal.process = termProc;

    termProc.stdout!.on("data", (chunk: Buffer) => {
      const sess = getSession(sessionId);
      const t = sess?.terminals.get(terminalId);
      if (!t || t.truncated) return;
      t.output += chunk.toString();
      if (t.output.length > t.outputByteLimit) {
        t.output = t.output.slice(t.output.length - t.outputByteLimit);
        t.truncated = true;
      }
      sendTerminalUpdate("in_progress");
    });

    termProc.stderr!.on("data", (chunk: Buffer) => {
      const sess = getSession(sessionId);
      const t = sess?.terminals.get(terminalId);
      if (!t || t.truncated) return;
      t.output += chunk.toString();
      if (t.output.length > t.outputByteLimit) {
        t.output = t.output.slice(t.output.length - t.outputByteLimit);
        t.truncated = true;
      }
      sendTerminalUpdate("in_progress");
    });

    termProc.on("exit", (code: number | null, sig: string | null) => {
      const sess = getSession(sessionId);
      const t = sess?.terminals.get(terminalId);
      if (t) {
        t.exitStatus = { exitCode: code, signal: sig ?? null };
        if (t.resolveExit) t.resolveExit();
      }
      sendTerminalUpdate(code === 0 ? "completed" : "failed");
    });

    termProc.on("error", () => {
      const sess = getSession(sessionId);
      const t = sess?.terminals.get(terminalId);
      if (t) {
        t.exitStatus = { exitCode: -1, signal: null };
        if (t.resolveExit) t.resolveExit();
      }
      sendTerminalUpdate("failed");
    });

    return { terminalId };
  };

  const onTerminalOutput = async (params: TerminalOutputRequest): Promise<TerminalOutputResponse> => {
    const currentSess = getSession(sessionId);
    if (!currentSess) throw new Error("session not found");
    const term = currentSess.terminals.get(params.terminalId);
    if (!term) throw new Error(`terminal not found: ${params.terminalId}`);
    return {
      output: term.output,
      truncated: term.truncated,
      exitStatus: term.exitStatus ?? undefined,
    };
  };

  const onWaitForTerminalExit = async (params: WaitForTerminalExitRequest): Promise<WaitForTerminalExitResponse> => {
    const currentSess = getSession(sessionId);
    if (!currentSess) throw new Error("session not found");
    const term = currentSess.terminals.get(params.terminalId);
    if (!term) throw new Error(`terminal not found: ${params.terminalId}`);
    await term.exitPromise;
    return {
      exitCode: term.exitStatus?.exitCode ?? null,
      signal: term.exitStatus?.signal ?? null,
    };
  };

  const onKillTerminal = async (params: KillTerminalRequest): Promise<KillTerminalResponse | void> => {
    const currentSess = getSession(sessionId);
    if (!currentSess) throw new Error("session not found");
    const term = currentSess.terminals.get(params.terminalId);
    if (!term) throw new Error(`terminal not found: ${params.terminalId}`);
    if (!term.process!.killed) {
      try {
        kill(term.process.pid!, "SIGTERM");
      } catch {}
    }
    return {};
  };

  const onReleaseTerminal = async (params: ReleaseTerminalRequest): Promise<ReleaseTerminalResponse | void> => {
    const currentSess = getSession(sessionId);
    if (!currentSess) throw new Error("session not found");
    const term = currentSess.terminals.get(params.terminalId);
    if (!term) throw new Error(`terminal not found: ${params.terminalId}`);
    if (!term.process!.killed) {
      try {
        kill(term.process.pid!, "SIGTERM");
      } catch {}
    }
    currentSess.terminals.delete(params.terminalId);
    // Clean up terminal's toolCallIdMap entry
    currentSess.toolCallIdMap.delete(params.terminalId);
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
