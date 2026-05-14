import type { WebSocket } from "ws";
import { getSession } from "../session.mjs";

export function handlePermissionResponse(
  ws: WebSocket,
  sessionId: string,
  requestId: string,
  outcome: string,
  optionId?: string,
): void {
  const sess = getSession(sessionId);
  if (!sess || !sess.pendingPermission) {
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

  const { resolve } = sess.pendingPermission;
  sess.pendingPermission = null;

  const validOutcomes = ["allow", "deny", "selected"];
  if (!validOutcomes.includes(outcome)) {
    ws.send(
      JSON.stringify({ type: "error", text: `Invalid outcome: ${outcome}` }),
    );
    return;
  }

  if (outcome === "selected" && optionId) {
    resolve({ outcome: { outcome: "selected" as const, optionId } });
  } else {
    resolve({ outcome: { outcome } });
  }
}
