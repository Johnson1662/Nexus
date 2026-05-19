import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs } from "../discovery/agents.mjs";
import { getLastModel, setLastModel } from "../prefs.mjs";
import {
  setSession,
  deleteSession,
  getSession,
  killSessionProcess,
  cleanupWsSessions,
} from "../session.mjs";
import { createAcpCallbacks } from "../acp-callbacks.mjs";
import type { SessionState } from "../acp/types.mjs";
import type { WebSocket } from "ws";

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
  const proc = spawn(agent, args, {
    cwd: cwd || process.cwd(),
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    shell: true,
  });

  const sessionId = `acp-${Date.now()}`;

  const sess: Partial<SessionState> = {
    ws,
    sessionId,
    process: proc,
    agent,
    cwd: cwd || process.cwd(),
    pendingPermission: null,
    terminals: new Map(),
    restartCount: 0,
  };

  const client = new AcpClient(proc, {
    onSessionUpdate: async (update) => {
      const type = update.update?.sessionUpdate || "unknown";
      console.log(`[server] agent_event type=${type} sessionId=${sessionId?.slice(0, 20)}`);
      try {
        ws.send(
          JSON.stringify({
            type: "agent_event",
            sessionId,
            event: update.update,
          }),
        );
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
          ws.send(
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
    ...createAcpCallbacks({ ws, sessionId, cwd: cwd || process.cwd() }),
  });

  sess.client = client;
  setSession(sessionId, sess as SessionState);

  proc.stderr.on("data", (chunk: Buffer) => {
    const text = chunk.toString();
    console.log(`[server] stderr: ${text.slice(0, 200)}`);
    try {
      ws.send(JSON.stringify({ type: "agent_stderr", sessionId, text }));
    } catch {}
  });

  proc.on("error", (err: Error) => {
    console.log(`[server] ${sessionId} spawn error: ${err.message}`);
    try {
      ws.send(
        JSON.stringify({ type: "error", text: `spawn failed: ${err.message}` }),
      );
    } catch {}
    deleteSession(sessionId);
  });

  proc.on("exit", (code: number | null) => {
    console.log(`[server] ${sessionId} exited with code ${code}`);
    try {
      ws.send(
        JSON.stringify({ type: "session_ended", sessionId, exitCode: code }),
      );
    } catch {}
    deleteSession(sessionId);
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
    if (sessionResult.models) {
      console.log(`[server] default model: ${sessionResult.models.currentModelId || "not set"}`);
    }
    if (sessionResult.configOptions) {
      const modelOpt = sessionResult.configOptions.find((o: any) => o.id === "model" || o.category === "model");
      if (modelOpt) console.log(`[server] agent default model: ${modelOpt.currentValue}`);
    }

    let effectiveModel = model || getLastModel(agent);
    if (!model && effectiveModel) {
      console.log(`[server] using last model: ${effectiveModel}`);
    }

    if (effectiveModel) {
      console.log(`[server] setting model to ${effectiveModel}`);
      await client.setSessionModel(acpSessionId, effectiveModel);
    }

    const models = (sessionResult as any).models?.availableModels || [];
    const modes = (sessionResult as any).modes?.availableModes || [];
    const mappedModels = models.map((m: any) => ({
      modelId: m.modelId,
      name: m.name,
    }));
    const mappedModes = modes.map((m: any) => ({
      value: m.id,
      name: m.name,
    }));

    try {
      ws.send(
        JSON.stringify({
          type: "model_list",
          models: mappedModels,
          modes: mappedModes,
        }),
      );
    } catch {}

    try {
      const sessionTitle = prompt ? prompt.slice(0, 50) + (prompt.length > 50 ? "\u2026" : "") : "New Session";
      ws.send(
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
      client.prompt(acpSessionId, prompt).then(
        (result) => {
          console.log(`[server] turn ended: ${result?.stopReason}`);
          try {
            ws.send(
              JSON.stringify({
                type: "turn_ended",
                sessionId,
                stopReason: result?.stopReason,
              }),
            );
          } catch {}
        },
        (err: unknown) => {
          const msg = err instanceof Error ? err.message : String(err);
          console.log(`[server] prompt error: ${msg}`);
          try {
            ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
            ws.send(JSON.stringify({ type: "error", sessionId, text: `Agent error: ${msg}` }));
          } catch {}
        },
      );
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.log(`[server] ACP init error: ${msg}`);
    try {
      ws.send(
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
