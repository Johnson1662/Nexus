import { handlePermissionResponse } from "./dist/handlers/permission.mjs";
import { sessionManager } from "./dist/session-manager.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed += 1;
  } else {
    failed += 1;
    console.error(`FAIL: ${message}`);
  }
}

function withPending(requestId, action) {
  const sent = [];
  let resolved;
  const transport = { send: (message) => sent.push(JSON.parse(message)) };
  const pending = { requestId, resolve: (value) => { resolved = value; } };
  const sessions = sessionManager.getAllSessions();
  const previous = sessions.get("session");
  sessions.set("session", { ownerTransport: transport, pendingPermission: pending });
  try {
    action({ sent, pending, resolved: () => resolved, transport });
  } finally {
    if (previous) sessions.set("session", previous);
    else sessions.delete("session");
  }
}

withPending("selected", ({ sent, pending, resolved, transport }) => {
  handlePermissionResponse(transport, "session", "selected", "selected", "option-1");
  assert(sent.length === 0, "selected does not send an error");
  assert(resolved()?.outcome?.outcome === "selected", "selected resolves as ACP selected");
  assert(resolved()?.outcome?.optionId === "option-1", "selected preserves optionId");
  assert(pending !== null, "test pending object remains inspectable");
});

withPending("cancelled", ({ sent, resolved, transport }) => {
  handlePermissionResponse(transport, "session", "cancelled", "cancelled");
  assert(sent.length === 0, "cancelled does not send an error");
  assert(resolved()?.outcome?.outcome === "cancelled", "cancelled resolves as ACP cancelled");
  assert(resolved()?.outcome?.optionId === undefined, "cancelled has no optionId");
});

for (const [outcome, optionId, label] of [
  ["allow", undefined, "legacy allow"],
  ["selected", undefined, "selected without optionId"],
  ["selected", "", "selected with empty optionId"],
]) {
  withPending("invalid", ({ sent, pending, resolved, transport }) => {
    handlePermissionResponse(transport, "session", "invalid", outcome, optionId);
    assert(sent[0]?.type === "error", `${label} sends an error`);
    assert(resolved() === undefined, `${label} does not resolve ACP`);
    assert(pending.requestId === "invalid", `${label} leaves pending request intact`);
  });
}

withPending("expected", ({ sent, pending, resolved, transport }) => {
  handlePermissionResponse(transport, "session", "wrong", "cancelled");
  assert(sent[0]?.type === "error", "request mismatch sends an error");
  assert(resolved() === undefined, "request mismatch does not resolve ACP");
  assert(pending.requestId === "expected", "request mismatch leaves pending request intact");
});

{
  const sent = [];
  const original = sessionManager.getSession;
  sessionManager.getSession = () => ({ pendingPermission: null });
  try {
    handlePermissionResponse({ send: (message) => sent.push(JSON.parse(message)) }, "session", "missing", "cancelled");
  } finally {
    sessionManager.getSession = original;
  }
  assert(sent[0]?.type === "error", "missing request sends an error");
}

console.log(`Permission Delegation: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
