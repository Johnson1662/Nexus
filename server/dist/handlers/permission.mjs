import { getSession } from "../session.mjs";
export function handlePermissionResponse(ws, sessionId, requestId, outcome, optionId) {
    const sess = getSession(sessionId);
    if (!sess || !sess.pendingPermission) {
        ws.send(JSON.stringify({ type: "error", text: "no pending permission request" }));
        return;
    }
    if (sess.pendingPermission.requestId !== requestId) {
        ws.send(JSON.stringify({ type: "error", text: "requestId mismatch" }));
        return;
    }
    const { resolve } = sess.pendingPermission;
    sess.pendingPermission = null;
    const validOutcomes = ["allow", "deny", "selected"];
    if (!validOutcomes.includes(outcome)) {
        ws.send(JSON.stringify({ type: "error", text: `Invalid outcome: ${outcome}` }));
        return;
    }
    if (outcome === "selected" && optionId) {
        resolve({ outcome: { outcome: "selected", optionId } });
    }
    else {
        resolve({ outcome: { outcome } });
    }
}
//# sourceMappingURL=permission.mjs.map