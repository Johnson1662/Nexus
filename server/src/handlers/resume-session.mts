import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import type { WebSocket } from "ws";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs, isValidAgent } from "../discovery/agents.mjs";
import {
  setSession,
  deleteSession,
  getSession,
  killSessionProcess,
  cleanupWsSessions,
  bufferAgentEvent,
} from "../session.mjs";
import { createAcpCallbacks } from "../acp-callbacks.mjs";
import type { SessionState } from "../acp/types.mjs";
import { extractModelList, setCachedModelList } from "../model-list.mjs";
import { recordToolCallIds } from "../tool-call-map.mjs";

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

  const bridgeSessionId = `acp-${Date.now()}-${randomUUID().slice(0, 8)}`;

  const sess: Partial<SessionState> = {
    ws,
    sessionId: bridgeSessionId,
    process: proc,
    agent,
    cwd: cwd || process.cwd(),
    pendingPermission: null,
    terminals: new Map(),
    toolCallIdMap: new Map(),
    orphanedAt: null,
    messageBuffer: [],
  };

  const client = new AcpClient(proc, {
    onSessionUpdate: async (update) => {
      const s = getSession(bridgeSessionId);
      if (s) {
        recordToolCallIds(s, update.update);
      }
      try {
        const eventPayload = {
          type: "agent_event",
          sessionId: bridgeSessionId,
          event: update.update,
        };
        bufferAgentEvent(bridgeSessionId, eventPayload);
        sess.ws?.send(JSON.stringify(eventPayload));
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
          sess.ws?.send(
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
    ...createAcpCallbacks({ sessionId: bridgeSessionId, cwd: cwd || process.cwd(), toolCallIdMap: sess.toolCallIdMap }),
  });

  sess.client = client;
  sess.loadedSessionId = targetSessionId;
  setSession(bridgeSessionId, sess as SessionState);

  proc.stderr.on("data", (chunk: Buffer) => {
    console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    try {
      sess.ws?.send(JSON.stringify({ type: "agent_stderr", sessionId: bridgeSessionId, text: chunk.toString() }));
    } catch {}
  });

  proc.on("error", (err: Error) => {
    console.log(`[server] ${bridgeSessionId} spawn error: ${err.message}`);
    deleteSession(bridgeSessionId);
  });

  proc.on("exit", (code: number | null) => {
    console.log(`[server] ${bridgeSessionId} exited with code ${code}`);
    try {
      sess.ws?.send(JSON.stringify({
        type: "session_ended", sessionId: bridgeSessionId, exitCode: code
      }));
    } catch {}
    if (sess.orphanedAt === null) {
      deleteSession(bridgeSessionId);
    }
  });

  try {
    console.log(`[server] initializing ACP for resume session ${targetSessionId}...`);
    await client.initialize();

    console.log(`[server] loading session ${targetSessionId} (via loadSession to replay history)`);
    const result = await client.loadSession(targetSessionId, cwd || process.cwd());
    sess.acpSessionId = targetSessionId;

    const modelList = extractModelList(result);
    setCachedModelList(agent, cwd || process.cwd(), modelList);
    if (modelList.models.length > 0 || modelList.modes.length > 0) {
      sess.ws?.send(JSON.stringify({ type: "model_list", models: modelList.models, modes: modelList.modes }));
    }

    if (model) {
      await client.setSessionModel(targetSessionId, model).catch(() => {});
    }

    sess.ws?.send(JSON.stringify({
      type: "session_started",
      sessionId: bridgeSessionId,
      agent,
      loadedSessionId: targetSessionId,
      resumed: true,
      ...(model ? { model } : {}),
    }));
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.log(`[server] resume_session error: ${msg}`);
    sess.ws?.send(JSON.stringify({ type: "error", text: `resume session failed: ${msg}` }));
    killSessionProcess(sess as SessionState);
    deleteSession(bridgeSessionId);
  }
}
