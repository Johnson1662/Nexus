import kill from "tree-kill";
import type { SessionState } from "./acp/types.mjs";

const sessions = new Map<string, SessionState>();
const wsOpQueues = new Map<import("ws").WebSocket, Promise<unknown>>();

// Maximum entries in toolCallIdMap to prevent unbounded growth per session
const MAX_TOOLCALL_IDS = 500;
// Idle session timeout: 15 minutes (background processes are killed after this)
const IDLE_TIMEOUT_MS = 15 * 60 * 1000;
// Maximum concurrent ACP processes per bridge (LRU eviction cap)
const MAX_ACP_PROCESSES = 5;
// Idle cleanup interval
const IDLE_CLEANUP_INTERVAL_MS = 30_000;

let idleCleanupTimer: ReturnType<typeof setInterval> | null = null;

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
    const excess = sess.messageBuffer.length - MAX_MESSAGE_BUFFER;
    sess.messageBuffer.splice(0, excess);
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
  updateSessionActivity(id);
}

/** Update the lastActivity timestamp for a session to now */
export function updateSessionActivity(sessionId: string): void {
  const sess = sessions.get(sessionId);
  if (sess) {
    sess.lastActivity = Date.now();
  }
}

export function deleteSession(id: string): void {
  const sess = sessions.get(id);
  if (sess) {
    killSessionProcess(sess);
    killTerminalProcesses(sess);
  }
  sessions.delete(id);
  sessionSeqCounter.delete(id);
}

export function findSessionForWs(ws: import("ws").WebSocket): SessionState | undefined {
  for (const [, sess] of sessions) {
    if (sess.ws === ws && sess.sessionId) {
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

/**
 * Cleanup all sessions associated with a WebSocket connection.
 * Sessions are orphaned (ws=null) but their ACP processes are KEPT ALIVE
 * for background execution. Idle cleanup or explicit close will kill them.
 */
export function cleanupWsSessions(ws: import("ws").WebSocket): void {
  for (const [id, sess] of sessions) {
    if (sess.ws === ws) {
      sess.orphanedAt = Date.now();
      sess.ws = null as unknown as import("ws").WebSocket;
      updateSessionActivity(id);
      console.log(`[session] session ${id.slice(0, 20)} orphaned (process kept alive for background execution)`);
      startIdleCleanup();
    }
  }
  wsOpQueues.delete(ws);
  enforceProcessPoolLimit();
}

/** Reclaim an orphaned session when WS reconnects with matching sessionId */
export function reclaimOrphanedSession(sessionId: string, newWs: import("ws").WebSocket): SessionState | undefined {
  const sess = sessions.get(sessionId);
  if (sess && sess.orphanedAt !== null) {
    sess.ws = newWs;
    sess.orphanedAt = null;
    updateSessionActivity(sessionId);
    console.log(`[session] reclaimed orphaned session ${sessionId.slice(0, 20)}`);
    return sess;
  }
  return undefined;
}

/**
 * Start the idle cleanup timer. Runs every 30s and kills sessions that have
 * been idle (no activity) for 15 minutes AND are not in an active turn.
 * Also enforces the max-5 concurrent ACP process limit.
 */
function startIdleCleanup(): void {
  if (idleCleanupTimer !== null) return;
  idleCleanupTimer = setInterval(() => {
    const now = Date.now();
    const toRemove: string[] = [];
    for (const [id, sess] of sessions) {
      // Skip sessions in an active turn — never kill mid-turn
      if (sess.turnActive) continue;
      // Only evict orphaned sessions (no WS connected); active sessions are not idle-evicted
      if (sess.orphanedAt === null) continue;
      const idleFor = now - sess.lastActivity;
      if (idleFor > IDLE_TIMEOUT_MS) {
        toRemove.push(id);
      }
    }
    for (const id of toRemove) {
      const sess = sessions.get(id);
      if (sess) {
        console.log(`[session] idle timeout: killing session ${id.slice(0, 20)} (idle ${Math.floor((Date.now() - sess.lastActivity) / 1000)}s)`);
        killTerminalProcesses(sess);
        killSessionProcess(sess);
        sessions.delete(id);
        sessionSeqCounter.delete(id);
      }
    }
    if (toRemove.length > 0) {
      console.log(`[session] idle cleanup removed ${toRemove.length} sessions`);
    }
    enforceProcessPoolLimit();
  }, IDLE_CLEANUP_INTERVAL_MS);
}

/**
 * LRU eviction: if more than MAX_ACP_PROCESSES ACP child processes are alive,
 * kill the oldest idle (non-turnActive) sessions until we're at the limit.
 * Active-turn sessions are never evicted.
 */
function enforceProcessPoolLimit(): void {
  const running: Array<{ id: string; lastActivity: number; turnActive: boolean }> = [];
  for (const [id, sess] of sessions) {
    if (sess.process && !sess.process.killed) {
      running.push({ id, lastActivity: sess.lastActivity || 0, turnActive: sess.turnActive });
    }
  }
  if (running.length <= MAX_ACP_PROCESSES) return;

  // Sort by lastActivity ascending (oldest first)
  running.sort((a, b) => a.lastActivity - b.lastActivity);

  // Evict oldest idle processes until under limit
  const toEvict: string[] = [];
  for (const entry of running) {
    if (entry.turnActive) continue;
    toEvict.push(entry.id);
    if (running.length - toEvict.length <= MAX_ACP_PROCESSES) break;
  }

  for (const id of toEvict) {
    const sess = sessions.get(id);
    if (sess) {
      console.log(`[session] LRU eviction: killing idle session ${id.slice(0, 20)}`);
      killTerminalProcesses(sess);
      killSessionProcess(sess);
      sessions.delete(id);
      sessionSeqCounter.delete(id);
    }
  }
}


export function getAllSessions(): Map<string, SessionState> {
  return sessions;
}
