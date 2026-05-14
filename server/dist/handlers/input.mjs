import { getSession } from "../session.mjs";
export function handleInput(ws, sessionId, text) {
    const sess = getSession(sessionId);
    if (!sess || !sess.acpSessionId) {
        ws.send(JSON.stringify({ type: "error", text: `no active session: ${sessionId}` }));
        return;
    }
    sess.client
        .prompt(sess.acpSessionId, text)
        .then((result) => {
        console.log(`[server] turn ended: ${result?.stopReason}`);
        ws.send(JSON.stringify({
            type: "turn_ended",
            sessionId,
            stopReason: result?.stopReason,
        }));
    })
        .catch((err) => {
        console.log(`[server] prompt error: ${err.message}`);
    });
}
//# sourceMappingURL=input.mjs.map