import kill from "tree-kill";
const sessions = new Map();
const wsOpQueues = new Map();
// Maximum entries in toolCallIdMap to prevent unbounded growth per session
const MAX_TOOLCALL_IDS = 500;
// Orphan session timeout: 5 minutes
const ORPHAN_TIMEOUT_MS = 5 * 60 * 1000;
// Maximum orphan sessions
const MAX_ORPHANS = 10;
// Orphan cleanup interval
const ORPHAN_CLEANUP_INTERVAL_MS = 30_000;
let orphanCleanupTimer = null;
// Per-session message sequence counter for messageId generation
const sessionSeqCounter = new Map();
// Maximum buffered messages per session (~10 turns worth)
const MAX_MESSAGE_BUFFER = 500;
/** Buffer an agent_event for cursor sync replay (Phase 3a) */
export function bufferAgentEvent(sessionId, eventPayload) {
    const sess = sessions.get(sessionId);
    if (!sess)
        return;
    let seq = (sessionSeqCounter.get(sessionId) || 0) + 1;
    sessionSeqCounter.set(sessionId, seq);
    const messageId = `${sessionId}:${seq}`;
    sess.messageBuffer.push({
        messageId,
        payload: JSON.stringify(eventPayload),
        timestamp: Date.now(),
    });
    // Sliding window: trim if over max
    if (sess.messageBuffer.length > MAX_MESSAGE_BUFFER) {
        sess.messageBuffer = sess.messageBuffer.slice(sess.messageBuffer.length - MAX_MESSAGE_BUFFER);
    }
}
/** Get buffered messages after a given messageId (cursor sync) */
export function getBufferedAfter(sessionId, lastMessageId) {
    const sess = sessions.get(sessionId);
    if (!sess)
        return [];
    let lastSeq = 0;
    if (lastMessageId) {
        const parts = lastMessageId.split(':');
        lastSeq = parseInt(parts[parts.length - 1]) || 0;
    }
    return sess.messageBuffer.filter((m) => {
        const mParts = m.messageId.split(':');
        const mSeq = parseInt(mParts[mParts.length - 1]) || 0;
        return mSeq > lastSeq;
    });
}
export function enqueueWsOp(ws, fn) {
    const prev = wsOpQueues.get(ws) || Promise.resolve();
    const next = prev.catch(() => { }).then(async () => {
        try {
            await fn();
        }
        catch (err) {
            console.log(`[server] queued op error: ${err.message}`);
        }
    });
    wsOpQueues.set(ws, next);
}
export function getSession(id) {
    return sessions.get(id);
}
export function setSession(id, sess) {
    sessions.set(id, sess);
}
export function deleteSession(id) {
    const sess = sessions.get(id);
    if (sess) {
        try {
            sess.client.destroy();
        }
        catch { }
        killTerminalProcesses(sess);
    }
    sessions.delete(id);
    sessionSeqCounter.delete(id);
}
export function findSessionForWs(ws) {
    for (const [, sess] of sessions) {
        if (sess.ws === ws && sess.acpSessionId) {
            return sess;
        }
    }
    return undefined;
}
export function killTerminalProcesses(sess) {
    if (!sess.terminals)
        return;
    for (const [, term] of sess.terminals) {
        if (term.process && !term.process.killed) {
            try {
                kill(term.process.pid, "SIGTERM");
            }
            catch { }
        }
    }
    sess.terminals.clear();
    // Clean all terminal-related entries from toolCallIdMap
    const terminalKeys = [];
    sess.toolCallIdMap.forEach((_v, k) => {
        if (k.startsWith("term-"))
            terminalKeys.push(k);
    });
    for (const k of terminalKeys)
        sess.toolCallIdMap.delete(k);
}
/** Trim toolCallIdMap to prevent memory leaks in long sessions. */
export function trimToolCallIds(sess) {
    if (sess.toolCallIdMap.size <= MAX_TOOLCALL_IDS)
        return;
    const entries = [...sess.toolCallIdMap.entries()];
    const toRemove = entries.slice(0, entries.length - MAX_TOOLCALL_IDS);
    for (const [key] of toRemove) {
        sess.toolCallIdMap.delete(key);
    }
}
export function killSessionProcess(sess) {
    try {
        sess.client.destroy();
    }
    catch { }
    if (sess.process && !sess.process.killed) {
        try {
            kill(sess.process.pid, "SIGTERM");
        }
        catch { }
    }
}
export function cleanupWsSessions(ws) {
    for (const [id, sess] of sessions) {
        if (sess.ws === ws) {
            // Phase 3a + Q4 grill: Don't kill processes on disconnect — keep Agent
            // running so reconnection can reclaim the session without restart.
            // Processes are killed after orphan timeout (5 min) in the cleanup timer.
            sess.orphanedAt = Date.now();
            console.log(`[session] session ${id.slice(0, 20)} orphaned (process kept alive), will keep for ${ORPHAN_TIMEOUT_MS / 1000}s`);
            // Start orphan cleanup timer if not already running
            startOrphanCleanup();
        }
    }
    // Enforce max orphans: kill oldest if over limit
    enforceOrphanLimit();
}
/** Reclaim an orphaned session when WS reconnects with matching sessionId */
export function reclaimOrphanedSession(sessionId, newWs) {
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
function startOrphanCleanup() {
    if (orphanCleanupTimer !== null)
        return;
    orphanCleanupTimer = setInterval(() => {
        const now = Date.now();
        const toRemove = [];
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
                console.log(`[session] cleaned up orphaned session ${id.slice(0, 20)}`);
            }
        }
        if (toRemove.length > 0)
            enforceOrphanLimit();
    }, ORPHAN_CLEANUP_INTERVAL_MS);
}
/** Enforce maximum orphan session limit: kill oldest if over limit */
function enforceOrphanLimit() {
    const orphans = [];
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
                console.log(`[session] evicted oldest orphan session ${id.slice(0, 20)}`);
            }
        }
    }
}
export function getAllSessions() {
    return sessions;
}
//# sourceMappingURL=session.mjs.map