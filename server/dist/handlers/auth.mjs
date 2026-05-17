import { getSession } from "../session.mjs";
export async function handleAuth(ws, sessionId, methodId) {
    const sess = getSession(sessionId);
    if (!sess) {
        ws.send(JSON.stringify({ type: "error", text: "session not found" }));
        return;
    }
    try {
        const result = await sess.client.authenticate(methodId);
        ws.send(JSON.stringify({ type: "auth_result", sessionId, result }));
    }
    catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        ws.send(JSON.stringify({ type: "error", text: `auth failed: ${msg}` }));
    }
}
//# sourceMappingURL=auth.mjs.map