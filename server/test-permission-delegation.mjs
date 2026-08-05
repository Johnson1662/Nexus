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
  const pending = { requestId, sessionId: "session", resolve: (value) => { resolved = value; } };
  const sessions = sessionManager.getAllSessions();
  const previous = sessions.get("session");
  sessions.set("session", {
    ownerTransport: transport,
    pendingPermissions: new Map([[requestId, pending]]),
  });
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
  sessionManager.getSession = () => ({ pendingPermissions: new Map() });
  try {
    handlePermissionResponse({ send: (message) => sent.push(JSON.parse(message)) }, "session", "missing", "cancelled");
  } finally {
    sessionManager.getSession = original;
  }
  assert(sent[0]?.type === "error", "missing request sends an error");
}

// 并发权限：同会话两个不同 requestId 互不覆盖，各自独立 resolve
{
  const sent = [];
  const r1 = [];
  const r2 = [];
  const transport = { send: (message) => sent.push(JSON.parse(message)) };
  const sessions = sessionManager.getAllSessions();
  const previous = sessions.get("session");
  sessions.set("session", {
    ownerTransport: transport,
    pendingPermissions: new Map([
      ["first", { requestId: "first", sessionId: "session", resolve: (v) => r1.push(v) }],
      ["second", { requestId: "second", sessionId: "session", resolve: (v) => r2.push(v) }],
    ]),
  });
  try {
    handlePermissionResponse(transport, "session", "second", "selected", "opt-2");
    handlePermissionResponse(transport, "session", "first", "cancelled");
    assert(r2.length === 1 && r2[0]?.outcome?.optionId === "opt-2", "second request resolves independently");
    assert(r1.length === 1 && r1[0]?.outcome?.outcome === "cancelled", "first request resolves independently");
    assert(sessions.get("session").pendingPermissions.size === 0, "both entries removed after resolution");
  } finally {
    if (previous) sessions.set("session", previous);
    else sessions.delete("session");
  }
}

console.log(`Permission Delegation: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
