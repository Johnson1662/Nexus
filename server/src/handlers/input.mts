import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";
import fs from "node:fs/promises";
import type { WebSocket } from "ws";
import { getSession, killTerminalProcesses } from "../session.mjs";
import { AcpClient } from "../acp/client.mjs";
import { getAgentLaunchArgs } from "../discovery/agents.mjs";

const PROMPT_TIMEOUT = 120 * 1000; // 2 minutes

function isPathWithinCwd(target: string, cwd: string): boolean {
  const resolved = path.resolve(target);
  const relative = path.relative(cwd, resolved);
  return !relative.startsWith("..") && !path.isAbsolute(relative);
}
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
  if (sess.acpSessionId && sess.client?.connected) return true;

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
  if (sess.process && !sess.process.killed) {
    try { (await import("tree-kill")).default(sess.process.pid!, "SIGTERM"); } catch {}
  }

  const cwd = sess.cwd || process.cwd();
  const args = getAgentLaunchArgs(sess.agent);
  const proc = spawn(sess.agent, args, {
    cwd,
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    shell: true,
  });

  const client = new AcpClient(proc, {
    onSessionUpdate: async (update) => {
      try {
        ws.send(JSON.stringify({ type: "agent_event", sessionId, event: update.update }));
      } catch {}
    },
    onPermissionRequest: (params) => {
      return new Promise((resolve) => {
        const requestId = randomUUID();
        const s = getSession(sessionId);
        if (s) s.pendingPermission = { requestId, resolve };
        try {
          ws.send(JSON.stringify({ type: "permission_request", sessionId, requestId, toolCall: params.toolCall, options: params.options }));
        } catch {}
      });
    },
    onReadTextFile: async (params) => {
      const s = getSession(sessionId);
      if (!s) throw new Error("session not found");
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
      const s = getSession(sessionId);
      if (!s) throw new Error("session not found");
      const effectiveCwd = (client.cwd || cwd) || process.cwd();
      if (!isPathWithinCwd(params.path, effectiveCwd)) {
        throw new Error(`path not allowed: ${params.path}`);
      }
      await fs.mkdir(path.dirname(params.path), { recursive: true });
      await fs.writeFile(params.path, params.content, "utf-8");
      return {};
    },
  });

  proc.stderr.on("data", (chunk: Buffer) => {
    console.log(`[server] stderr: ${chunk.toString().slice(0, 200)}`);
  });
  proc.on("error", () => {});
  proc.on("exit", (code) => {
    console.log(`[server] ${sessionId} restarted process exited with code ${code}`);
  });

  await client.initialize();
  const result = await client.createSession(cwd);
  const acpSessionId = result.sessionId;

  sess.process = proc;
  sess.client = client;
  sess.acpSessionId = acpSessionId;
  sess.pendingPermission = null;

  console.log(`[server] ACP session restarted: ${sessionId} → ${acpSessionId}`);
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

  // Auto-recover if ACP connection is dead
  if (!sess.acpSessionId || !sess.client?.connected) {
    ensureSessionAlive(ws, sessionId).then((ok) => {
      if (!ok) {
        ws.send(JSON.stringify({ type: "error", text: "failed to restart session" }));
        return;
      }
      // Retry prompt on the revived session
      doPrompt(ws, sessionId, text);
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
  if (!sess || !sess.acpSessionId) return;

  console.log(`[server] calling ACP prompt (acpSessionId=${sess.acpSessionId}, text="${text.slice(0, 50)}")`);

  const startTime = Date.now();
  let timedOut = false;
  let errorDetected = false;

  let stderrHandler: ((chunk: Buffer) => void) | null = null;
  if (sess.process?.stderr) {
    stderrHandler = (chunk: Buffer) => {
      if (errorDetected || timedOut) return;
      const stderrText = chunk.toString();
      for (const pattern of MODEL_ERROR_PATTERNS) {
        if (pattern.test(stderrText)) {
          errorDetected = true;
          console.log(`[server] model error detected: ${stderrText.slice(0, 200)}`);
          sess.client.cancel(sess.acpSessionId).catch(() => {});
          sess.client.destroy();
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
    console.log(`[server] prompt TIMEOUT after ${Date.now() - startTime}ms for ${sessionId}`);
    if (stderrHandler && sess.process?.stderr) {
      try { sess.process.stderr.removeListener("data", stderrHandler); } catch {}
    }
    sess.client.cancel(sess.acpSessionId).catch(() => {});
    sess.client.destroy();
    ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "timeout" }));
    ws.send(JSON.stringify({ type: "error", sessionId, text: `[Timeout] No response in 15s. Switch model and try again.` }));
  }, PROMPT_TIMEOUT);

  sess.client.prompt(sess.acpSessionId, text)
    .then((result) => {
      if (timedOut || errorDetected) return;
      clearTimeout(timer);
      if (stderrHandler && sess.process?.stderr) {
        try { sess.process.stderr.removeListener("data", stderrHandler); } catch {}
      }
      console.log(`[server] turn ended after ${Math.floor((Date.now() - startTime) / 1000)}s: ${result?.stopReason}`);
      ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: result?.stopReason }));
    })
    .catch((err: Error) => {
      if (timedOut || errorDetected) return;
      clearTimeout(timer);
      if (stderrHandler && sess.process?.stderr) {
        try { sess.process.stderr.removeListener("data", stderrHandler); } catch {}
      }
      const msg = err?.message || String(err);
      console.log(`[server] prompt error after ${Math.floor((Date.now() - startTime) / 1000)}s: ${msg}`);
      ws.send(JSON.stringify({ type: "turn_ended", sessionId, stopReason: "error" }));
      ws.send(JSON.stringify({ type: "error", sessionId, text: msg.includes("closed") || msg.includes("abort")
        ? `[Session expired] Send a message to auto-restart.` : `Agent error: ${msg}` }));
    });
}
