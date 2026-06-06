import kill from "tree-kill";
import type { SessionState } from "./acp/types.mjs";

const sessions = new Map<string, SessionState>();
const wsOpQueues = new Map<import("ws").WebSocket, Promise<unknown>>();

// Maximum entries in toolCallIdMap to prevent unbounded growth per session
const MAX_TOOLCALL_IDS = 500;
// Orphan session timeout: 5 minutes
const ORPHAN_TIMEOUT_MS = 5 * 60 * 1000;
// Maximum orphan sessions
const MAX_ORPHANS = 10;
// Orphan cleanup interval
const ORPHAN_CLEANUP_INTERVAL_MS = 30_000;

let orphanCleanupTimer: ReturnType<typeof setInterval> | null = null;

// Per-session message sequence counter for messageId generation
const sessionSeqCounter = new Map<string, number>();
// Maximum buffered messages per session (~10 turns worth)
const MAX_MESSAGE_BUFFER = 500;

/** Buffer an agent_event for cursor sync replay (Phase 3a) */
export function bufferAgentEvent(sessionId: string, eventPayload: object): string | undefined {
  const sess = sessions.get(sessionId);
  if (!sess) return undefined;
  let seq = (sessionSeqCounter.get(sessionId) || 0) + 1;
  sessionSeqCounter.set(sessionId, seq);
  const messageId = `${sessionId}:${seq}`;
  (eventPayload as { messageId?: string }).messageId = messageId;
  sess.messageBuffer.push({
    messageId,
    payload: JSON.stringify(eventPayload),
    timestamp: Date.now(),
  });
  // Sliding window: trim if over max
  if (sess.messageBuffer.length > MAX_MESSAGE_BUFFER) {
    sess.messageBuffer = sess.messageBuffer.slice(
      sess.messageBuffer.length - MAX_MESSAGE_BUFFER,
    );
  }
  return messageId;
}

/** Get buffered messages after a given messageId (cursor sync) */
export function getBufferedAfter(
  sessionId: string,
  lastMessageId: string,
): { entries: Array<{ messageId: string; payload: string; timestamp: number }>; overflow: boolean } {
  const sess = sessions.get(sessionId);
  if (!sess) return { entries: [], overflow: false };
  let lastSeq = 0;
  if (lastMessageId) {
    const parts = lastMessageId.split(':');
    lastSeq = parseInt(parts[parts.length - 1]) || 0;
  }
  let firstBufferedSeq = 0;
  if (sess.messageBuffer.length > 0) {
    const firstParts = sess.messageBuffer[0].messageId.split(':');
    firstBufferedSeq = parseInt(firstParts[firstParts.length - 1]) || 0;
  }
  const overflow = lastSeq > 0 && firstBufferedSeq > 0 && lastSeq < firstBufferedSeq - 1;
  const entries = sess.messageBuffer.filter((m) => {
    const mParts = m.messageId.split(':');
    const mSeq = parseInt(mParts[mParts.length - 1]) || 0;
    return mSeq > lastSeq;
  });
  return { entries, overflow };
}

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
  sessionSeqCounter.delete(id);
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
  // Clean all terminal-related entries from toolCallIdMap
  const terminalKeys: string[] = [];
  sess.toolCallIdMap.forEach((_v, k) => {
    if (k.startsWith("term-")) terminalKeys.push(k);
  });
  for (const k of terminalKeys) sess.toolCallIdMap.delete(k);
}

/** Trim toolCallIdMap to prevent memory leaks in long sessions. */
export function trimToolCallIds(sess: SessionState): void {
  if (sess.toolCallIdMap.size <= MAX_TOOLCALL_IDS) return;
  const entries = [...sess.toolCallIdMap.entries()];
  const toRemove = entries.slice(0, entries.length - MAX_TOOLCALL_IDS);
  for (const [key] of toRemove) {
    sess.toolCallIdMap.delete(key);
  }
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
      sess.orphanedAt = Date.now();
      sess.ws = null as unknown as import("ws").WebSocket;
      console.log(`[session] session ${id.slice(0, 20)} orphaned (process kept alive), will keep for ${ORPHAN_TIMEOUT_MS / 1000}s`);
      startOrphanCleanup();
    }
  }
  wsOpQueues.delete(ws);
  enforceOrphanLimit();
}

/** Reclaim an orphaned session when WS reconnects with matching sessionId */
export function reclaimOrphanedSession(sessionId: string, newWs: import("ws").WebSocket): SessionState | undefined {
  const sess = sessions.get(sessionId);
  if (sess && sess.orphanedAt !== null) {
    sess.ws = newWs;
    sess.orphanedAt = null;
    console.log(`[session] reclaimed orphaned session ${sessionId.slice(0, 20)}`);
    return sess;
  }
  return undefined;
}

/** Periodically clean up orphaned sessions that have exceeded the timeout */
function startOrphanCleanup(): void {
  if (orphanCleanupTimer !== null) return;
  orphanCleanupTimer = setInterval(() => {
    const now = Date.now();
    const toRemove: string[] = [];
    for (const [id, sess] of sessions) {
      if (sess.orphanedAt !== null && (now - sess.orphanedAt) > ORPHAN_TIMEOUT_MS) {
        toRemove.push(id);
      }
    }
    for (const id of toRemove) {
      const sess = sessions.get(id);
      if (sess) {
        killTerminalProcesses(sess);
        killSessionProcess(sess);
        sessions.delete(id);
        sessionSeqCounter.delete(id);
        console.log(`[session] cleaned up orphaned session ${id.slice(0, 20)}`);
      }
    }
    if (toRemove.length > 0) enforceOrphanLimit();
  }, ORPHAN_CLEANUP_INTERVAL_MS);
}

/** Enforce maximum orphan session limit: kill oldest if over limit */
function enforceOrphanLimit(): void {
  const orphans: Array<{ id: string; orphanedAt: number }> = [];
  for (const [id, sess] of sessions) {
    if (sess.orphanedAt !== null) {
      orphans.push({ id, orphanedAt: sess.orphanedAt });
    }
  }
  if (orphans.length > MAX_ORPHANS) {
    orphans.sort((a, b) => a.orphanedAt - b.orphanedAt);
    const toRemove = orphans.slice(0, orphans.length - MAX_ORPHANS);
    for (const { id } of toRemove) {
      const sess = sessions.get(id);
      if (sess) {
        killTerminalProcesses(sess);
        killSessionProcess(sess);
        sessions.delete(id);
        sessionSeqCounter.delete(id);
        console.log(`[session] evicted oldest orphan session ${id.slice(0, 20)}`);
      }
    }
  }
}

export function getAllSessions(): Map<string, SessionState> {
  return sessions;
}
