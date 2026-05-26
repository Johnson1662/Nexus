import kill from "tree-kill";
const sessions = new Map();
const wsOpQueues = new Map();
// Maximum entries in toolCallIdMap to prevent unbounded growth per session
const MAX_TOOLCALL_IDS = 500;
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
            killTerminalProcesses(sess);
            killSessionProcess(sess);
            sessions.delete(id);
        }
    }
}
export function getAllSessions() {
    return sessions;
}
//# sourceMappingURL=session.mjs.map