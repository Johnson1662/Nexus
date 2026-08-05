import { EventEmitter } from "node:events";
import { execPath } from "node:process";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) passed += 1;
  else {
    failed += 1;
    console.error(`FAIL: ${message}`);
  }
}

function ws() {
  const socket = new EventEmitter();
  socket.sent = [];
  socket.send = (message) => socket.sent.push(message);
  return socket;
}

function messages(socket) {
  return socket.sent.map((message) => JSON.parse(message));
}

async function main() {
  // Give the injected factory a deterministic, inert child process without
  // touching the developer's real ~/.nexus agent configuration.
  const originalHome = process.env.HOME;
  const originalUserProfile = process.env.USERPROFILE;
  const testHome = mkdtempSync(join(tmpdir(), "nexus-session-callbacks-"));
  mkdirSync(join(testHome, ".nexus"), { recursive: true });
  writeFileSync(
    join(testHome, ".nexus", "installed-agents.json"),
    JSON.stringify({
      agents: [{
        agentId: "callback-test-agent",
        installedAt: Date.now(),
        source: "custom",
        customCommand: execPath,
        customArgs: ["-e", "setInterval(() => {}, 1000)"],
      }],
    }),
  );
  process.env.HOME = testHome;
  process.env.USERPROFILE = testHome;

  const {
    SessionManager,
    sessionManager: globalSessionManager,
  } = await import("./dist/session-manager.mjs");
  const { handlePermissionResponse } = await import("./dist/handlers/permission.mjs");

  const sessionId = "real-session-id";
  const captured = [];
  const fakeClient = (callbacks) => ({
    connected: true,
    initialize: async () => ({}),
    createSession: async () => {
      // The map has no key while ACP is creating a new session. This event
      // must still reach the connection that initiated creation.
      await callbacks.onSessionUpdate({
        sessionId: "",
        update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "early" } },
      });
      return { sessionId };
    },
    loadSession: async () => ({}),
    resumeSession: async () => ({}),
    setSessionModel: async () => ({}),
    closeSession: async () => ({}),
    cancel: async () => { },
    destroy: () => { },
  });
  const manager = new SessionManager({
    create: (_proc, callbacks) => {
      captured.push(callbacks);
      return fakeClient(callbacks);
    },
  });

  const owner = ws();
  const session = await manager.getOrCreate(owner, {
    agent: "callback-test-agent",
    cwd: process.cwd(),
  });
  const callbacks = captured[0];
  assert(messages(owner).some((message) => message.type === "agent_event" && message.event?.sessionUpdate === "agent_message_chunk"), "creation-time event uses wsRef while session map is empty");

  // createAcpCallbacks is shared with the global manager, so expose this
  // test session there as the production singleton would be exposed.
  const globalSessions = globalSessionManager.getAllSessions();
  const previousGlobal = globalSessions.get(sessionId);
  globalSessions.set(sessionId, session);

  try {
    // P0-1: file callbacks must use the ACP id assigned after createSession.
    await callbacks.onReadTextFile({ path: "package.json" });
    const toolUpdate = messages(owner).find(
      (message) => message.type === "agent_event" && message.event?.sessionUpdate === "tool_call_update",
    );
    assert(toolUpdate?.sessionId === sessionId, "tool callback event carries the real ACP session id");

    // P0-3: two concurrent permission requests retain independent resolvers.
    const first = callbacks.onPermissionRequest({
      toolCall: { toolCallId: "tool-1", title: "first" },
      options: [{ optionId: "allow-first", name: "Allow" }],
    });
    const second = callbacks.onPermissionRequest({
      toolCall: { toolCallId: "tool-2", title: "second" },
      options: [{ optionId: "allow-second", name: "Allow" }],
    });
    assert(session.pendingPermissions.size === 2, "concurrent permission requests are both retained");

    const permissionMessages = messages(owner).filter((message) => message.type === "permission_request");
    const firstRequest = permissionMessages.at(-2);
    const secondRequest = permissionMessages.at(-1);
    handlePermissionResponse(owner, sessionId, secondRequest.requestId, "selected", "allow-second");
    handlePermissionResponse(owner, sessionId, firstRequest.requestId, "cancelled");
    const [firstResult, secondResult] = await Promise.all([first, second]);
    assert(firstResult.outcome?.outcome === "cancelled", "first permission resolves as cancelled");
    assert(secondResult.outcome?.outcome === "selected" && secondResult.outcome.optionId === "allow-second", "second permission resolves as selected");
    assert(session.pendingPermissions.size === 0, "resolved permission requests are removed from the map");

    // P0-2: once orphaned, events are buffered for reclaim and never sent to
    // the stale transport. A later owner receives new events normally.
    manager.cleanupWsSessions(owner);
    const sentBeforeOrphanEvent = owner.sent.length;
    await callbacks.onSessionUpdate({
      sessionId,
      update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "orphaned" } },
    });
    assert(owner.sent.length === sentBeforeOrphanEvent, "orphaned session does not send events to the old WebSocket");

    const reclaimed = ws();
    assert(manager.reclaimOrphanedSession(sessionId, reclaimed) === session, "orphaned session can be reclaimed");
    await callbacks.onSessionUpdate({
      sessionId,
      update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "reclaimed" } },
    });
    assert(reclaimed.sent.length === 1, "reclaimed owner receives subsequent events");
    await manager.close(sessionId, reclaimed);
  } finally {
    if (previousGlobal) globalSessions.set(sessionId, previousGlobal);
    else globalSessions.delete(sessionId);
    manager.stop();
    if (originalHome === undefined) delete process.env.HOME;
    else process.env.HOME = originalHome;
    if (originalUserProfile === undefined) delete process.env.USERPROFILE;
    else process.env.USERPROFILE = originalUserProfile;
  }

  console.log(`Session callbacks: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
