import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";
import type { WebSocket } from "ws";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs, isValidAgent } from "../discovery/agents.mjs";
import {
  setSession,
  deleteSession,
  getSession,
  killSessionProcess,
  cleanupWsSessions,
} from "../session.mjs";
import { createAcpCallbacks } from "../acp-callbacks.mjs";
import type { SessionState } from "../acp/types.mjs";

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

  if (!isValidAgent(agent)) {
    ws.send(JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }));
    return;
  }

  cleanupWsSessions(ws);

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
    toolCallIdMap: new Map(),
  };

  const client = new AcpClient(proc, {
    onSessionUpdate: async (update) => {
      const toolCallEvt = update.update as any;
      if (toolCallEvt?.sessionUpdate === "tool_call" && toolCallEvt?.toolCallId) {
        const s = getSession(bridgeSessionId);
        if (s) {
          const rawId = String(toolCallEvt.toolCallId);
          const locations = (toolCallEvt.locations || []) as Array<{ path: string }>;
          const rawInput = toolCallEvt.rawInput as Record<string, unknown> | undefined;
          for (const loc of locations) {
            if (loc.path) {
              const rp = path.resolve(loc.path);
              s.toolCallIdMap.set(`read:${rp}`, rawId);
              s.toolCallIdMap.set(`write:${rp}`, rawId);
            }
          }
          if (locations.length === 0 && rawInput && typeof rawInput.path === "string") {
            const rp = path.resolve(rawInput.path as string);
            if (toolCallEvt.kind === "read") {
              s.toolCallIdMap.set(`read:${rp}`, rawId);
            } else if (toolCallEvt.kind === "edit") {
              s.toolCallIdMap.set(`write:${rp}`, rawId);
            } else {
              s.toolCallIdMap.set(`read:${rp}`, rawId);
              s.toolCallIdMap.set(`write:${rp}`, rawId);
            }
          }
          s.lastToolCallId = rawId;
        }
      }
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
    ...createAcpCallbacks({ ws, sessionId: bridgeSessionId, cwd: cwd || process.cwd(), toolCallIdMap: sess.toolCallIdMap }),
  });

  sess.client = client;
  sess.loadedSessionId = targetSessionId;
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
    sess.acpSessionId = targetSessionId;

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
