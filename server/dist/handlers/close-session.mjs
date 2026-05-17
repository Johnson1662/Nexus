import { getSession, deleteSession, killSessionProcess } from "../session.mjs";
export async function handleCloseSession(ws, sessionId) {
    const sess = getSession(sessionId);
    if (!sess) {
        ws.send(JSON.stringify({ type: "error", text: "session not found" }));
        return;
    }
    try {
        await sess.client.closeSession(sess.acpSessionId);
    }
    catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        console.log(`[server] closeSession error: ${msg}`);
    }
    killSessionProcess(sess);
    deleteSession(sessionId);
    ws.send(JSON.stringify({ type: "session_closed", sessionId }));
}
//# sourceMappingURL=close-session.mjs.map