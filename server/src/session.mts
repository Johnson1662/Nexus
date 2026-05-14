import kill from "tree-kill";
import type { SessionState } from "./acp/types.mjs";

const sessions = new Map<string, SessionState>();

export function getSession(id: string): SessionState | undefined {
  return sessions.get(id);
}

export function setSession(id: string, sess: SessionState): void {
  sessions.set(id, sess);
}

export function deleteSession(id: string): void {
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

export function killSessionProcess(sess: SessionState): void {
  if (sess.process && !sess.process.killed) {
    try {
      kill(sess.process.pid!, "SIGTERM");
    } catch {}
  }
}

export function cleanupWsSessions(ws: import("ws").WebSocket): void {
  for (const [id, sess] of sessions) {
    if (sess.ws === ws) {
      killSessionProcess(sess);
      sess.client.destroy();
      sessions.delete(id);
    }
  }
}

export function killOldWsSessions(ws: import("ws").WebSocket): void {
  for (const [id, sess] of sessions) {
    if (sess.ws === ws) {
      killSessionProcess(sess);
      sess.client.destroy();
      sessions.delete(id);
    }
  }
}

export function getAllSessions(): Map<string, SessionState> {
  return sessions;
}
