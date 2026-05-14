import kill from "tree-kill";
const sessions = new Map();
export function getSession(id) {
    return sessions.get(id);
}
export function setSession(id, sess) {
    sessions.set(id, sess);
}
export function deleteSession(id) {
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
export function killSessionProcess(sess) {
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
            killSessionProcess(sess);
            sess.client.destroy();
            sessions.delete(id);
        }
    }
}
export function killOldWsSessions(ws) {
    for (const [id, sess] of sessions) {
        if (sess.ws === ws) {
            killSessionProcess(sess);
            sess.client.destroy();
            sessions.delete(id);
        }
    }
}
export function getAllSessions() {
    return sessions;
}
//# sourceMappingURL=session.mjs.map