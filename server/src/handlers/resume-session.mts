import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";
import fs from "node:fs/promises";
import type { WebSocket } from "ws";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs } from "../discovery/agents.mjs";
import {
  setSession,
  deleteSession,
  getSession,
  killSessionProcess,
  killOldWsSessions,
} from "../session.mjs";
import type { SessionState } from "../acp/types.mjs";

function isPathWithinCwd(target: string, cwd: string): boolean {
  const resolved = path.resolve(target);
  const relative = path.relative(cwd, resolved);
  return !relative.startsWith("..") && !path.isAbsolute(relative);
}

export async function handleResumeSession(
  ws: WebSocket,
  params: {
    sessionId: string;
    cwd?: string;
    agent?: string;
    model?: string;
  },
): Promise<void> {
  const { sessionId: targetSessionId, cwd, agent = "opencode", model } = params;

  if (!targetSessionId) {
    ws.send(JSON.stringify({ type: "error", text: "sessionId is required" }));
    return;
  }

  killOldWsSessions(ws);

  const args = getAgentLaunchArgs(agent);
  const proc = spawn(agent, args, {
    cwd: cwd || process.cwd(),
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    shell: true,
  });

  const bridgeSessionId = `acp-${Date.now()}`;

  const sess: Partial<SessionState> = {
    ws,
    sessionId: bridgeSessionId,
    process: proc,
    agent,
    cwd: cwd || process.cwd(),
    pendingPermission: null,
    terminals: new Map(),
  };

  const client = new AcpClient(proc, {
    onSessionUpdate: async (update) => {
      try {
        ws.send(
          JSON.stringify({
            type: "agent_event",
            sessionId: bridgeSessionId,
            event: update.update,
          }),
        );
      } catch {}
    },
    onPermissionRequest: (params) => {
      return new Promise((resolve) => {
        const requestId = randomUUID();
        const currentSess = getSession(bridgeSessionId);
        if (currentSess) {
          currentSess.pendingPermission = { requestId, resolve };
        }
        try {
          ws.send(
            JSON.stringify({
              type: "permission_request",
              sessionId: bridgeSessionId,
              requestId,
              toolCall: params.toolCall,
              options: params.options,
            }),
          );
        } catch {}
      });
    },
    onReadTextFile: async (params) => {
      const currentSess = getSession(bridgeSessionId);
      if (!currentSess) throw new Error("session not found");
      const effectiveCwd = (client.cwd || cwd) || process.cwd();
      if (!isPathWithinCwd(params.path, effectiveCwd)) {
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
      return { content };
    },
    onWriteTextFile: async (params) => {
      const currentSess = getSession(bridgeSessionId);
      if (!currentSess) throw new Error("session not found");
      const effectiveCwd = (client.cwd || cwd) || process.cwd();
      if (!isPathWithinCwd(params.path, effectiveCwd)) {
        throw new Error(`path not allowed: ${params.path}`);
      }
      await fs.mkdir(path.dirname(params.path), { recursive: true });
      await fs.writeFile(params.path, params.content, "utf-8");
      return {};
    },
    onCreateTerminal: async (params) => {
      const currentSess = getSession(bridgeSessionId);
      if (!currentSess) throw new Error("session not found");
      const terminalId = `term-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      const outputByteLimit = params.outputByteLimit ?? 100000;
      let resolveExit: (() => void) | null = null;
      const exitPromise = new Promise<void>((resolve) => { resolveExit = resolve; });
      const terminal = { id: terminalId, process: null as any, output: "", truncated: false, exitStatus: null as { exitCode: number | null; signal: string | null } | null, exitPromise, resolveExit, outputByteLimit };
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
      termProc.stdout!.on("data", (chunk: Buffer) => {
        const sess = getSession(bridgeSessionId);
        const t = sess?.terminals.get(terminalId);
        if (!t || t.truncated) return;
        t.output += chunk.toString();
        if (t.output.length > t.outputByteLimit) {
          t.output = t.output.slice(t.output.length - t.outputByteLimit);
          t.truncated = true;
        }
      });
      termProc.stderr!.on("data", (chunk: Buffer) => {
        const sess = getSession(bridgeSessionId);
        const t = sess?.terminals.get(terminalId);
        if (!t || t.truncated) return;
        t.output += chunk.toString();
        if (t.output.length > t.outputByteLimit) {
          t.output = t.output.slice(t.output.length - t.outputByteLimit);
          t.truncated = true;
        }
      });
      termProc.on("exit", (code: number | null, sig: string | null) => {
        const sess = getSession(bridgeSessionId);
        const t = sess?.terminals.get(terminalId);
        if (t) { t.exitStatus = { exitCode: code, signal: sig ?? null }; if (t.resolveExit) t.resolveExit(); }
      });
      termProc.on("error", () => {
        const sess = getSession(bridgeSessionId);
        const t = sess?.terminals.get(terminalId);
        if (t) { t.exitStatus = { exitCode: -1, signal: null }; if (t.resolveExit) t.resolveExit(); }
      });
      return { terminalId };
    },
    onTerminalOutput: async (params) => {
      const currentSess = getSession(bridgeSessionId);
      if (!currentSess) throw new Error("session not found");
      const term = currentSess.terminals.get(params.terminalId);
      if (!term) throw new Error(`terminal not found: ${params.terminalId}`);
      return { output: term.output, truncated: term.truncated, exitStatus: term.exitStatus ?? undefined };
    },
    onWaitForTerminalExit: async (params) => {
      const currentSess = getSession(bridgeSessionId);
      if (!currentSess) throw new Error("session not found");
      const term = currentSess.terminals.get(params.terminalId);
      if (!term) throw new Error(`terminal not found: ${params.terminalId}`);
      await term.exitPromise;
      return { exitCode: term.exitStatus?.exitCode ?? null, signal: term.exitStatus?.signal ?? null };
    },
    onKillTerminal: async (params) => {
      const currentSess = getSession(bridgeSessionId);
      if (!currentSess) throw new Error("session not found");
      const term = currentSess.terminals.get(params.terminalId);
      if (!term) throw new Error(`terminal not found: ${params.terminalId}`);
      if (!term.process!.killed) {
        try { const { default: kill } = await import("tree-kill"); kill(term.process.pid!, "SIGTERM"); } catch {}
      }
      return {};
    },
    onReleaseTerminal: async (params) => {
      const currentSess = getSession(bridgeSessionId);
      if (!currentSess) throw new Error("session not found");
      const term = currentSess.terminals.get(params.terminalId);
      if (!term) throw new Error(`terminal not found: ${params.terminalId}`);
      if (!term.process!.killed) {
        try { const { default: kill } = await import("tree-kill"); kill(term.process.pid!, "SIGTERM"); } catch {}
      }
      currentSess.terminals.delete(params.terminalId);
      return {};
    },
  });

  sess.client = client;
  setSession(bridgeSessionId, sess as SessionState);

  proc.stderr.on("data", (chunk: Buffer) => {
    console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    try {
      ws.send(JSON.stringify({ type: "agent_stderr", sessionId: bridgeSessionId, text: chunk.toString() }));
    } catch {}
  });

  proc.on("error", (err: Error) => {
    console.log(`[server] ${bridgeSessionId} spawn error: ${err.message}`);
    deleteSession(bridgeSessionId);
  });

  proc.on("exit", (code: number | null) => {
    console.log(`[server] ${bridgeSessionId} exited with code ${code}`);
    deleteSession(bridgeSessionId);
  });

  try {
    console.log(`[server] initializing ACP for resume session ${targetSessionId}...`);
    await client.initialize();

    console.log(`[server] resuming session ${targetSessionId}`);
    await client.resumeSession(targetSessionId, cwd || process.cwd());

    if (model) {
      await client.setSessionModel(targetSessionId, model).catch(() => {});
    }

    ws.send(JSON.stringify({
      type: "session_started",
      sessionId: bridgeSessionId,
      agent,
      loadedSessionId: targetSessionId,
      resumed: true,
    }));
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.log(`[server] resume_session error: ${msg}`);
    ws.send(JSON.stringify({ type: "error", text: `resume session failed: ${msg}` }));
    killSessionProcess(sess as SessionState);
    deleteSession(bridgeSessionId);
  }
}
