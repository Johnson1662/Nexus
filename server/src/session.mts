import kill from "tree-kill";
import type { SessionState } from "./acp/types.mjs";

const sessions = new Map<string, SessionState>();

const wsOpQueues = new Map<import("ws").WebSocket, Promise<unknown>>();

export function enqueueWsOp(ws: import("ws").WebSocket, fn: () => Promise<void>): void {
  const prev = wsOpQueues.get(ws) || Promise.resolve();
  const next = prev.catch(() => {}).then(async () => {
    try {
      await fn();
    } catch (err: any) {
      console.log(`[server] queued op error: ${err.message}`);
    }
  });
  wsOpQueues.set(ws, next);
}

export function getSession(id: string): SessionState | undefined {
  return sessions.get(id);
}

export function setSession(id: string, sess: SessionState): void {
  sessions.set(id, sess);
}

export function deleteSession(id: string): void {
  const sess = sessions.get(id);
  if (sess) {
    try { sess.client.destroy(); } catch {}
    killTerminalProcesses(sess);
  }
  sessions.delete(id);
}

export function findSessionForWs(ws: import("ws").WebSocket): SessionState | undefined {
  for (const [, sess] of sessions) {
    if (sess.ws === ws && sess.acpSessionId) {
      return sess;
    }
  }
  return undefined;
}

export function killTerminalProcesses(sess: SessionState): void {
  if (!sess.terminals) return;
  for (const [, term] of sess.terminals) {
    if (term.process && !term.process.killed) {
      try {
        kill(term.process.pid!, "SIGTERM");
      } catch {}
    }
  }
  sess.terminals.clear();
}

export function killSessionProcess(sess: SessionState): void {
  try { sess.client.destroy(); } catch {}
  if (sess.process && !sess.process.killed) {
    try {
      kill(sess.process.pid!, "SIGTERM");
    } catch {}
  }
}

export function cleanupWsSessions(ws: import("ws").WebSocket): void {
  for (const [id, sess] of sessions) {
    if (sess.ws === ws) {
      killTerminalProcesses(sess);
      killSessionProcess(sess);
      sessions.delete(id);
    }
  }
}

export function getAllSessions(): Map<string, SessionState> {
  return sessions;
}
