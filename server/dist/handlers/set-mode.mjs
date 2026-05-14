import { getSession } from "../session.mjs";
export async function handleSetMode(ws, sessionId, modeId) {
    const sess = getSession(sessionId);
    if (!sess || !sess.acpSessionId) {
        ws.send(JSON.stringify({ type: "error", text: "no active session" }));
        return;
    }
    try {
        await sess.client.setSessionMode(sess.acpSessionId, modeId);
        ws.send(JSON.stringify({ type: "mode_set", sessionId, modeId }));
    }
    catch (err) {
        ws.send(JSON.stringify({ type: "error", text: `set_mode failed: ${err.message}` }));
    }
}
//# sourceMappingURL=set-mode.mjs.map