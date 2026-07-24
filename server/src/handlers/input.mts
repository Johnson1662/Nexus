import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import kill from "tree-kill";
import type { WebSocket } from "ws";
import { getSession, setSession, killTerminalProcesses, killSessionProcess, bufferAgentEvent, updateSessionActivity } from "../session.mjs";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs } from "../discovery/agents.mjs";
import { createAcpCallbacks } from "../acp-callbacks.mjs";
import { getLastModel } from "../prefs.mjs";
import { recordToolCallIds } from "../tool-call-map.mjs";

const PROMPT_TIMEOUT = 120 * 1000; // 2 minutes
const MODEL_ERROR_PATTERNS: RegExp[] = [
  /rate limit/i, /quota/i, /429/i, /402/i, /insufficient_quota/i,
  /resource.*exhausted/i, /too many request/i, /billing/i,
  /credit.*exhausted/i, /payment required/i, /model.*not.*found/i,
  /model.*unavailable/i, /api.*error/i, /auth.*error/i,
  /unauthorized/i, /forbidden/i, /403/i, /401/i, /\b5[0-9]{2}\b/i,
];

async function ensureSessionAlive(ws: WebSocket, sessionId: string): Promise<boolean> {
  const sess = getSession(sessionId);
  if (!sess) return false;
  updateSessionActivity(sessionId);
  if (sess.sessionId && sess.client?.connected) return true;

  // Cap restart attempts to prevent infinite loop
  sess.restartCount = (sess.restartCount || 0) + 1;
  if (sess.restartCount > 2) {
    console.log(`[server] too many restarts for ${sessionId}, giving up`);
    ws.send(JSON.stringify({ type: "error", sessionId, text: "Agent keeps crashing. Please reconnect manually." }));
    return false;
  }

  // ACP connection is dead — restart
  console.log(`[server] ACP connection dead for ${sessionId}, restarting...`);

  killTerminalProcesses(sess);
  try { sess.client?.destroy(); } catch {}
  if (sess.process) {
    // Remove old listeners to prevent exit handler from deleting the session
    sess.process.removeAllListeners("exit");
    sess.process.removeAllListeners("error");
    if (!sess.process.killed) {
      try { kill(sess.process.pid!, "SIGTERM"); } catch {}
    }
  }

  const cwd = sess.cwd || process.cwd();
  const args = getAgentLaunchArgs(sess.agent);
  const proc = spawn(sess.agent, args, {
    cwd,
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    shell: true,
  });

  let suppressingReplay = false;

  const client = new AcpClient(proc, {
    onSessionUpdate: async (update) => {
      if (suppressingReplay) return; // skip history replay during loadSession
      const s = getSession(sessionId);
      if (s) {
        recordToolCallIds(s, update.update);
        updateSessionActivity(sessionId);
      }
      // Q5 grill: parallel send + buffer — bufferAgentEvent runs
      // independently even if ws.send() fails (disconnected WS).
      const eventPayload = { type: "agent_event", sessionId, event: update.update };
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
        const s = getSession(sessionId);
        if (s) s.pendingPermission = { requestId, resolve };
        try {
          sess.ws?.send(JSON.stringify({ type: "permission_request", sessionId, requestId, toolCall: params.toolCall, options: params.options }));
        } catch {}
      });
    },
    ...createAcpCallbacks({ sessionId, cwd, toolCallIdMap: sess.toolCallIdMap }),
  });

  proc.stderr.on("data", (chunk: Buffer) => {
    console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
  });
  proc.on("error", () => {});
  proc.on("exit", (code) => {
    console.log(`[server] ${sessionId} restarted process exited with code ${code}`);
  });

  await client.initialize();

  // Try to reload existing session first to avoid creating orphaned sessions in the agent's store
  const reloadSessionId = sess.sessionId;

  let acpSessionId: string;
  if (reloadSessionId) {
    suppressingReplay = true;
    try {
      console.log(`[server] reloading session ${reloadSessionId}...`);
      await client.loadSession(reloadSessionId, cwd);
      acpSessionId = reloadSessionId;
    } catch (err) {
      // Session no longer exists on agent — create a fresh one
      console.log(`[server] loadSession failed, creating new session: ${err instanceof Error ? err.message : String(err)}`);
      const result = await client.createSession(cwd);
      acpSessionId = result.sessionId;
    } finally {
      suppressingReplay = false;
    }
  } else {
    console.log(`[server] creating new session...`);
    const result = await client.createSession(cwd);
    acpSessionId = result.sessionId;
  }

  sess.process = proc;
  sess.client = client;
  sess.sessionId = acpSessionId;
  sess.pendingPermission = null;
  sess.restartCount = 0;

  const lastModel = getLastModel(sess.agent);
  if (lastModel) {
    client.setSessionModel(sess.sessionId, lastModel).catch((err: Error) => {
      console.log(`[server] restore model failed: ${err.message}`);
    });
  }

  // Re-insert into map in case old exit handler deleted it
  setSession(sessionId, sess);

  console.log(`[server] ACP session restarted: ${sessionId}`);
  return true;
}

export function handleInput(
  ws: WebSocket,
  sessionId: string,
  text: string,
): void {
  const sess = getSession(sessionId);
  if (!sess) {
    ws.send(JSON.stringify({ type: "error", text: `session not found: ${sessionId}` }));
    return;
  }
  updateSessionActivity(sessionId);

  // Auto-recover if ACP connection is dead
  if (!sess.sessionId || !sess.client?.connected) {
    ensureSessionAlive(ws, sessionId).then((ok) => {
      if (!ok) {
        ws.send(JSON.stringify({ type: "error", text: "failed to restart session" }));
        return;
      }
      // Retry prompt on the revived session
      doPrompt(ws, sessionId, text);
    }).catch((err: Error) => {
      console.log(`[server] ensureSessionAlive error: ${err.message}`);
      try {
        ws.send(JSON.stringify({ type: "error", sessionId, text: `Failed to restore session: ${err.message}` }));
      } catch {}
    });
    return;
  }

  doPrompt(ws, sessionId, text);
}

function doPrompt(
  ws: WebSocket,
  sessionId: string,
  text: string,
): void {
  const sess = getSession(sessionId);
  if (!sess || !sess.sessionId) {
    console.log(`[server] doPrompt: session not found or no sessionId for ${sessionId}`);
    try {
      ws.send(JSON.stringify({ type: "error", sessionId, text: `session lost while sending message` }));
    } catch {}
    return;
  }

  // Mark turn active
  sess.turnActive = true;

  console.log(`[server] calling ACP prompt (sessionId=${sess.sessionId}, text="${text.slice(0, 50)}")`);

  const startTime = Date.now();
  let timedOut = false;
  let errorDetected = false;

  const keepAlive = setInterval(() => {
    if (timedOut || errorDetected) return;
    try { ws.send(JSON.stringify({ type: "heartbeat", sessionId, ts: Date.now() })); } catch {}
  }, 3000);

  let stderrHandler: ((chunk: Buffer) => void) | null = null;
  if (sess.process?.stderr) {
    stderrHandler = (chunk: Buffer) => {
      if (errorDetected || timedOut) return;
      const stderrText = chunk.toString();
      for (const pattern of MODEL_ERROR_PATTERNS) {
        if (pattern.test(stderrText)) {
          errorDetected = true;
          clearInterval(keepAlive);
          clearTimeout(timer);
          console.log(`[server] model error detected: ${stderrText.slice(0, 200)}`);
sess.client.cancel(sess.sessionId).catch(() => {});
          const modelErrorSess = getSession(sessionId);
          if (modelErrorSess) modelErrorSess.turnActive = false;
          bufferAgentEvent(sessionId, { type: "agent_event", sessionId, event: { sessionUpdate: 'turn_ended', stopReason: "error" } });
          ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
          ws.send(JSON.stringify({ type: "error", sessionId, text: `Model error: ${stderrText.slice(0, 300).trim()}` }));
          break;
        }
      }
    };
    sess.process.stderr.on("data", stderrHandler);
  }

  const timer = setTimeout(() => {
    if (errorDetected) return;
    timedOut = true;
    clearInterval(keepAlive);
    console.log(`[server] prompt TIMEOUT after ${Date.now() - startTime}ms for ${sessionId}`);
    if (stderrHandler && sess.process?.stderr) {
      try { sess.process.stderr.removeListener("data", stderrHandler); } catch {}
    }
    sess.client.cancel(sess.sessionId).catch(() => {});
    const timeoutSess = getSession(sessionId);
    if (timeoutSess) timeoutSess.turnActive = false;
    bufferAgentEvent(sessionId, { type: "agent_event", sessionId, event: { sessionUpdate: 'turn_ended', stopReason: "timeout" } });
    ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "timeout" }));
    ws.send(JSON.stringify({ type: "error", sessionId, text: `[Timeout] No response in 2 minutes. Switch model and try again.` }));

  }, PROMPT_TIMEOUT);

  sess.client.prompt(sess.sessionId, text)
    .then((result) => {
      if (timedOut || errorDetected) return;
      clearInterval(keepAlive);
      clearTimeout(timer);
      if (stderrHandler && sess.process?.stderr) {
        try { sess.process.stderr.removeListener("data", stderrHandler); } catch {}
      }
      const s = getSession(sessionId);
      if (s) s.turnActive = false;
      console.log(`[server] turn ended after ${Math.floor((Date.now() - startTime) / 1000)}s: ${result?.stopReason}`);
      bufferAgentEvent(sessionId, { type: "agent_event", sessionId, event: { sessionUpdate: 'turn_ended', stopReason: result?.stopReason } });
      ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: result?.stopReason }));
    })

    .catch((err: Error) => {
      if (timedOut || errorDetected) return;
      clearInterval(keepAlive);
      clearTimeout(timer);
      if (stderrHandler && sess.process?.stderr) {
        try { sess.process.stderr.removeListener("data", stderrHandler); } catch {}
      }
      const s = getSession(sessionId);
      if (s) s.turnActive = false;
      const msg = err?.message || String(err);
      console.log(`[server] prompt error after ${Math.floor((Date.now() - startTime) / 1000)}s: ${msg}`);
      bufferAgentEvent(sessionId, { type: "agent_event", sessionId, event: { sessionUpdate: 'turn_ended', stopReason: "error" } });
      ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
      ws.send(JSON.stringify({ type: "error", sessionId, text: msg.includes("closed") || msg.includes("abort")
        ? `[Session expired] Send a message to auto-restart.` : `Agent error: ${msg}` }));
    });
}
