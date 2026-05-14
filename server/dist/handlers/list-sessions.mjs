import { findSessionForWs } from "../session.mjs";
const sessionListCache = new Map();
export async function handleListSessions(ws, cwd) {
    const sess = findSessionForWs(ws);
    if (!sess) {
        ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
        return;
    }
    const cached = sessionListCache.get(ws);
    if (cached && Date.now() - cached.timestamp < 30000) {
        ws.send(JSON.stringify({ type: "session_list", sessions: cached.sessions }));
        return;
    }
    ws.send(JSON.stringify({ type: "session_list", sessions: [] }));
    try {
        const result = await sess.client.listSessions(cwd);
        const sessions = result.sessions || [];
        sessionListCache.set(ws, { sessions, timestamp: Date.now() });
        ws.send(JSON.stringify({ type: "session_list", sessions }));
    }
    catch (err) {
        console.log(`[server] list_sessions error: ${err.message}`);
    }
}
export function clearSessionListCache(ws) {
    sessionListCache.delete(ws);
}
//# sourceMappingURL=list-sessions.mjs.map