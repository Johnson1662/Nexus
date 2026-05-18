import kill from "tree-kill";
const sessions = new Map();
const wsOpQueues = new Map();
export function enqueueWsOp(ws, fn) {
    const prev = wsOpQueues.get(ws) || Promise.resolve();
    const next = prev.then(async () => {
        try {
            await fn();
        }
        catch (err) {
            console.log(`[server] queued op error: ${err.message}`);
        }
    }, async () => {
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
export function killOldWsSessions(ws) {
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