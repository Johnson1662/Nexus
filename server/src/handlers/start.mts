import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs } from "../discovery/agents.mjs";
import { getLastModel } from "../prefs.mjs";
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
import type { WebSocket } from "ws";
import { extractModelList, setCachedModelList } from "../model-list.mjs";
import { recordToolCallIds } from "../tool-call-map.mjs";
import { sessionTitleOverrides, clearSessionListCache } from "./list-sessions.mjs";

interface StartParams {
  agent?: string;
  prompt?: string;
  cwd?: string;
  model?: string;
}

export async function handleStart(
  ws: WebSocket,
  params: StartParams,
): Promise<void> {
  const { agent = "opencode", prompt, cwd, model } = params;

  console.log(`[server] starting agent: ${agent}`);

  cleanupWsSessions(ws);

  const args = getAgentLaunchArgs(agent);
  const ANYWHERE_DIR = join(homedir(), '.anywhere');
  mkdirSync(ANYWHERE_DIR, { recursive: true });
  const resolvedCwd = cwd && existsSync(cwd) ? cwd : ANYWHERE_DIR;
  const proc = spawn(agent, args, {
    cwd: resolvedCwd,
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    windowsHide: true,
    shell: true,
  });

  const sessionId = `acp-${Date.now()}-${randomUUID().slice(0, 8)}`;

  const sess: Partial<SessionState> = {
    ws,
    sessionId,
    process: proc,
    agent,
    cwd: cwd || process.cwd(),
    pendingPermission: null,
    terminals: new Map(),
    restartCount: 0,
    toolCallIdMap: new Map(),
    orphanedAt: null,
    messageBuffer: [],
  };

  const client = new AcpClient(proc, {
    onSessionUpdate: async (update) => {
      const currentSess = getSession(sessionId);
      if (currentSess) {
        recordToolCallIds(currentSess, update.update);
      }
      // Q5 grill: parallel send + buffer — bufferAgentEvent runs
      // independently even if ws.send() fails (disconnected WS).
      const eventPayload = {
        type: "agent_event",
        sessionId,
        event: update.update,
      };
      try {
        bufferAgentEvent(sessionId, eventPayload);
      } catch {}
      try {
        sess.ws?.send(JSON.stringify(eventPayload));
      } catch {}
    },
    onPermissionRequest: (params) => {
      return new Promise((resolve) => {
        const requestId = randomUUID();
        const currentSess = getSession(sessionId);
        if (currentSess) {
          currentSess.pendingPermission = { requestId, resolve };
        }
        try {
          sess.ws?.send(
            JSON.stringify({
              type: "permission_request",
              sessionId,
              requestId,
              toolCall: params.toolCall,
              options: params.options,
            }),
          );
        } catch {}
      });
    },
    ...createAcpCallbacks({ sessionId, cwd: cwd || process.cwd(), toolCallIdMap: sess.toolCallIdMap }),
  });

  sess.client = client;
  setSession(sessionId, sess as SessionState);

  proc.stderr.on("data", (chunk: Buffer) => {
    const text = chunk.toString();
    console.log(`[server] stderr: ${text.slice(0, 200)}`);
    try {
      sess.ws?.send(JSON.stringify({ type: "agent_stderr", sessionId, text }));
    } catch {}
  });

  proc.on("error", (err: Error) => {
    console.log(`[server] ${sessionId} spawn error: ${err.message}`);
    try {
      sess.ws?.send(
        JSON.stringify({ type: "error", text: `spawn failed: ${err.message}` }),
      );
    } catch {}
    deleteSession(sessionId);
  });

  proc.on("exit", (code: number | null) => {
    console.log(`[server] ${sessionId} exited with code ${code}`);
    try {
      sess.ws?.send(
        JSON.stringify({ type: "session_ended", sessionId, exitCode: code }),
      );
    } catch {}
    if (sess.orphanedAt === null) {
      deleteSession(sessionId);
    }
  });

  try {
    console.log(`[server] initializing ACP for ${sessionId}...`);
    const initResult = await client.initialize();
    console.log(`[server] ACP initialized, agent: ${initResult?.agentInfo?.name}`);

    console.log(`[server] creating session for ${sessionId}...`);
    const sessionResult = await client.createSession(cwd || process.cwd());
    const acpSessionId = sessionResult.sessionId;
    sess.acpSessionId = acpSessionId;
    console.log(`[server] ACP session created: ${acpSessionId}`);
    if (sessionResult.modes) {
      console.log(`[server] default mode: ${sessionResult.modes.currentModeId || "not set"}`);
    }
    if (sessionResult.configOptions) {
      const modelOpt = sessionResult.configOptions.find((o: any) => o.id === "model" || o.category === "model");
      if (modelOpt) console.log(`[server] agent default model: ${modelOpt.currentValue}`);
    }

    const modelList = extractModelList(sessionResult);
    setCachedModelList(agent, cwd || process.cwd(), modelList);
    try {
      sess.ws?.send(
        JSON.stringify({
          type: "model_list",
          models: modelList.models,
          modes: modelList.modes,
        }),
      );
    } catch {}

    const effectiveModel = model || getLastModel(agent);
    if (!model && effectiveModel) {
      console.log(`[server] using last model: ${effectiveModel}`);
    }

    try {
      const sessionTitle = prompt ? prompt.slice(0, 50) + (prompt.length > 50 ? "…" : "") : "New Session";
      if (acpSessionId) {
        sessionTitleOverrides.set(acpSessionId, sessionTitle);
        clearSessionListCache(ws);
      }
      sess.ws?.send(
        JSON.stringify({
          type: "session_started",
          sessionId,
          agent,
          prompt,
          acpSessionId,
          ...(effectiveModel ? { model: effectiveModel } : {}),
          title: sessionTitle,
        }),
      );
    } catch {}

    if (prompt) {
      if (effectiveModel) {
        try {
          console.log(`[server] setting model to ${effectiveModel} via configOption`);
          await client.setSessionConfigOption(acpSessionId, "model", effectiveModel);
        } catch (_) {
          try {
            console.log(`[server] configOption failed, trying setSessionModel`);
            await client.setSessionModel(acpSessionId, effectiveModel);
          } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : String(err);
            console.log(`[server] set initial model failed: ${msg}`);
            try {
              bufferAgentEvent(sessionId, { type: "agent_event", sessionId, event: { sessionUpdate: "turn_ended", stopReason: "error" } });
              sess.ws?.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
              sess.ws?.send(JSON.stringify({ type: "error", sessionId, text: `model setup failed: ${msg}` }));
            } catch {}
            return;
          }
        }
      }
      // Keep WS alive while agent processes (mobile carrier NAT timeout workaround)
      const keepAlive = setInterval(() => {
        try { sess.ws?.send(JSON.stringify({ type: "heartbeat", sessionId, ts: Date.now() })); } catch {}
      }, 3000);
      client.prompt(acpSessionId, prompt).then(
        (result) => {
          clearInterval(keepAlive);
          console.log(`[server] turn ended: ${result?.stopReason}`);
          try {
            bufferAgentEvent(sessionId, { type: "agent_event", sessionId, event: { sessionUpdate: "turn_ended", stopReason: result?.stopReason } });
            sess.ws?.send(
              JSON.stringify({
                type: "turn_ended",
                sessionId,
                stopReason: result?.stopReason,
              }),
            );
          } catch {}
        },

        (err: unknown) => {
          clearInterval(keepAlive);
          const msg = err instanceof Error ? err.message : String(err);
          console.log(`[server] prompt error: ${msg}`);
          try {
            bufferAgentEvent(sessionId, { type: "agent_event", sessionId, event: { sessionUpdate: "turn_ended", stopReason: "error" } });
            sess.ws?.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
            sess.ws?.send(JSON.stringify({ type: "error", sessionId, text: `Agent error: ${msg}` }));
          } catch {}
        },

      );
    } else if (effectiveModel) {
      console.log(`[server] restoring model to ${effectiveModel}`);
      client.setSessionConfigOption(acpSessionId, "model", effectiveModel).catch(() => {
        client.setSessionModel(acpSessionId, effectiveModel).catch((err: Error) => {
          console.log(`[server] restore model failed: ${err.message}`);
          try {
            sess.ws?.send(JSON.stringify({ type: "error", sessionId, text: `model restore failed: ${err.message}` }));
          } catch {}
        });
      });
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.log(`[server] ACP init error: ${msg}`);
    try {
      sess.ws?.send(
        JSON.stringify({
          type: "error",
          text: `ACP initialization failed: ${msg}`,
        }),
      );
    } catch {}
    killSessionProcess(sess as SessionState);
    deleteSession(sessionId);
  }
}
