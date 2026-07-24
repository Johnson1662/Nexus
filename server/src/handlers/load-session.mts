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
  updateSessionActivity,
  getAllSessions,
  getBufferedAfter,
} from "../session.mjs";
import { createAcpCallbacks } from "../acp-callbacks.mjs";
import type { SessionState } from "../acp/types.mjs";
import { extractModelList, setCachedModelList } from "../model-list.mjs";
import { recordToolCallIds } from "../tool-call-map.mjs";

export async function handleLoadSession(
  ws: WebSocket,
  params: {
    sessionId: string;
    cwd?: string;
    agent?: string;
    model?: string;
    lastMessageId?: string;
  },
): Promise<void> {
  const { sessionId: targetSessionId, cwd, agent = "opencode", model, lastMessageId } = params;

  if (!targetSessionId) {
    ws.send(JSON.stringify({ type: "error", text: "sessionId is required" }));
    return;
  }

  if (!isValidAgent(agent)) {
    ws.send(JSON.stringify({ type: "error", text: `Unknown agent: ${agent}` }));
    return;
  }

  cleanupWsSessions(ws);

  // Check if this targetSessionId is already running in the process pool
  for (const [existingId, existingSess] of getAllSessions()) {
    if (
      existingSess.sessionId === targetSessionId
      && existingSess.process && !existingSess.process.killed
    ) {
      console.log(`[server] reusing existing session ${existingId.slice(0, 20)} for target ${targetSessionId.slice(0, 20)}`);
      // Attach WS to the existing session and un-orphan it
      existingSess.ws = ws;
      existingSess.orphanedAt = null;
      updateSessionActivity(existingId);
      ws.send(JSON.stringify({
        type: "session_started",
        sessionId: existingId,
        agent: existingSess.agent,
        resumed: true,
      }));

      // Replay buffered events since lastMessageId
      if (lastMessageId) {
        const syncResult = getBufferedAfter(existingId, lastMessageId);
        if (syncResult.entries.length > 0) {
          const safeEntries = syncResult.entries
            .map(e => {
              try {
                const parsed = JSON.parse(e.payload);
                const payload = parsed.event || parsed;
                if (payload && typeof payload === "object") {
                  payload.messageId = e.messageId;
                }
                return { messageId: e.messageId, payload, timestamp: e.timestamp };
              } catch {
                return null;
              }
            })
            .filter(Boolean);
          ws.send(JSON.stringify({
            type: "sync_response",
            sessionId: existingId,
            entries: safeEntries,
            overflow: syncResult.overflow,
          }));
          console.log(`[server] replayed ${safeEntries.length} buffered events for ${targetSessionId.slice(0, 20)}`);
        }
      }
      return;
    }
  }

  const args = getAgentLaunchArgs(agent);
  const proc = spawn(agent, args, {
    cwd: cwd || process.cwd(),
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    shell: true,
  });

  const sess: Partial<SessionState> = {
    ws,
    sessionId: targetSessionId,
    process: proc,
    agent,
    cwd: cwd || process.cwd(),
    pendingPermission: null,
    terminals: new Map(),
    toolCallIdMap: new Map(),
    orphanedAt: null,
    turnActive: false,
    lastActivity: Date.now(),
    messageBuffer: [],
  };

  const client = new AcpClient(proc, {
    onSessionUpdate: async (update) => {
      const s = getSession(targetSessionId);
      if (s) {
        recordToolCallIds(s, update.update);
        updateSessionActivity(targetSessionId);
      }
      try {
        const eventPayload = {
          type: "agent_event",
          sessionId: targetSessionId,
          event: update.update,
        };
        bufferAgentEvent(targetSessionId, eventPayload);
        sess.ws?.send(JSON.stringify(eventPayload));
      } catch {}
    },
    onPermissionRequest: (params) => {
      return new Promise((resolve) => {
        const requestId = randomUUID();
        const currentSess = getSession(targetSessionId);
        if (currentSess) {
          currentSess.pendingPermission = { requestId, resolve };
        }
        try {
          sess.ws?.send(
            JSON.stringify({
              type: "permission_request",
              sessionId: targetSessionId,
              requestId,
              toolCall: params.toolCall,
              options: params.options,
            }),
          );
        } catch {}
      });
    },
    ...createAcpCallbacks({ sessionId: targetSessionId, cwd: cwd || process.cwd(), toolCallIdMap: sess.toolCallIdMap }),
  });

  sess.client = client;
  setSession(targetSessionId, sess as SessionState);

  proc.stderr.on("data", (chunk: Buffer) => {
    console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
    try {
      sess.ws?.send(
        JSON.stringify({
          type: "agent_stderr",
          sessionId: targetSessionId,
          text: chunk.toString(),
        }),
      );
    } catch {}
  });

  proc.on("error", (err: Error) => {
    console.log(`[server] ${targetSessionId} spawn error: ${err.message}`);
    deleteSession(targetSessionId);
  });

  proc.on("exit", (code: number | null) => {
    console.log(`[server] ${targetSessionId} exited with code ${code}`);
    try {
      sess.ws?.send(JSON.stringify({
        type: "session_ended", sessionId: targetSessionId, exitCode: code
      }));
    } catch {}
    if (sess.orphanedAt === null) {
      deleteSession(targetSessionId);
    }
  });

  try {
    console.log(`[server] initializing ACP for load session ${targetSessionId}...`);
    await client.initialize();

    console.log(`[server] loading session ${targetSessionId}`);
    const loadResult = await client.loadSession(targetSessionId, cwd || process.cwd());

    const modelList = extractModelList(loadResult);
    setCachedModelList(agent, cwd || process.cwd(), modelList);
    if (modelList.models.length > 0 || modelList.modes.length > 0) {
      sess.ws?.send(JSON.stringify({ type: "model_list", models: modelList.models, modes: modelList.modes }));
    }

    if (model) {
      await client.setSessionModel(targetSessionId, model).catch(() => {});
    }

    sess.ws?.send(
      JSON.stringify({
        type: "session_started",
        sessionId: targetSessionId,
        agent,
        ...(model ? { model } : {}),
      }),
    );
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.log(`[server] load_session error: ${msg}`);
    sess.ws?.send(
      JSON.stringify({
        type: "error",
        text: `load session failed: ${msg}`,
      }),
    );
    killSessionProcess(sess as SessionState);
    deleteSession(targetSessionId);
  }
}
