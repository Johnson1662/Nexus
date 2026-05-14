import { getSession } from "../session.mjs";
export function handleCancel(ws, sessionId) {
    const sess = getSession(sessionId);
    if (!sess)
        return;
    sess.client.cancel(sess.acpSessionId).catch(() => { });
    ws.send(JSON.stringify({ type: "session_cancelled", sessionId }));
}
//# sourceMappingURL=cancel.mjs.map