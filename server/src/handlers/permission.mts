import type { WebSocket } from "ws";
import { SessionOwnerError, sessionManager } from "../session-manager.mjs";

const CANONICAL_OUTCOMES = ["selected", "cancelled"];

export function handlePermissionResponse(
  ws: WebSocket,
  sessionId: string,
  requestId: string,
  outcome: string,
  optionId?: string,
): void {
  let sess;
  try {
    sess = sessionManager.assertOwner(sessionId, ws);
  } catch (err: unknown) {
    const code = err instanceof SessionOwnerError ? err.code : "SESSION_ACCESS_DENIED";
    const message = err instanceof Error ? err.message : String(err);
    ws.send(JSON.stringify({ type: "error", sessionId, code, text: message }));
    return;
  }
  if (!sess.pendingPermission) {
    ws.send(
      JSON.stringify({ type: "error", text: "no pending permission request" }),
    );
    return;
  }

  if (sess.pendingPermission.requestId !== requestId) {
    ws.send(
      JSON.stringify({ type: "error", text: "requestId mismatch" }),
    );
    return;
  }

  // Validate outcome BEFORE touching session state
  if (!CANONICAL_OUTCOMES.includes(outcome)) {
    ws.send(
      JSON.stringify({ type: "error", text: `Invalid outcome: ${outcome}` }),
    );
    return;
  }

  if (outcome === "selected") {
    const selectedOptionId = optionId?.trim();
    if (!selectedOptionId) {
      ws.send(
        JSON.stringify({ type: "error", text: "selected outcome requires a non-empty optionId" }),
      );
      return;
    }
    const { resolve } = sess.pendingPermission;
    sess.pendingPermission = null;
    resolve({ outcome: { outcome: "selected" as const, optionId: selectedOptionId } });
    return;
  }

  const { resolve } = sess.pendingPermission;
  sess.pendingPermission = null;
  resolve({ outcome: { outcome: "cancelled" as const } });
}
