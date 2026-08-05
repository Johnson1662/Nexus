import { SessionManager } from "./dist/session-manager.mjs";

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

function transport() {
  const messages = [];
  return {
    messages,
    send(message) {
      messages.push(JSON.parse(message));
    },
  };
}

function fakeSession(sessionId, ownerTransport, overrides = {}) {
  return {
    ws: ownerTransport,
    ownerTransport,
    ownerId: null,
    client: {
      cancel: () => Promise.resolve(),
      closeSession: () => Promise.resolve(),
      destroy: () => { },
    },
    sessionId,
    cwd: process.cwd(),
    process: { killed: true },
    agent: "test",
    pendingPermissions: new Map(),
    terminals: new Map(),
    restartCount: 0,
    toolCallIdMap: new Map(),
    turnActive: false,
    lastActivity: Date.now(),
    orphanedAt: null,
    messageBuffer: [],
    ...overrides,
  };
}

const manager = new SessionManager();
const sessions = manager.getAllSessions();

// cancel() immediately voids all permission waits without ending the turn.
{
  const ws = transport();
  const resolved = [];
  const pendingPermissions = new Map(
    ["one", "two"].map((requestId) => [requestId, {
      requestId,
      sessionId: "cancel-session",
      resolve: (value) => resolved.push(value),
    }]),
  );
  sessions.set("cancel-session", fakeSession("cancel-session", ws, {
    turnActive: true,
    pendingPermissions,
  }));
  manager.cancel("cancel-session", ws);
  assert(resolved.length === 2, "cancel resolves both pending permissions");
  assert(resolved.every((value) => value?.outcome?.outcome === "cancelled"), "cancel resolves permissions as cancelled");
  assert(pendingPermissions.size === 0, "cancel clears pending permissions");
  assert(sessions.get("cancel-session").turnActive === true, "cancel leaves turnActive for prompt resolution");
  sessions.delete("cancel-session");
}

// finishTurn() releases state once and emits both buffered and live turn_ended frames.
{
  const ws = transport();
  const session = fakeSession("finish-session", ws, {
    turnActive: true,
    resetTimeout: () => { },
  });
  sessions.set("finish-session", session);
  const before = session.messageBuffer.length;
  manager.finishTurn("finish-session", "end_turn");
  const buffered = session.messageBuffer[before];
  const payload = JSON.parse(buffered.payload);
  assert(session.turnActive === false, "finishTurn clears turnActive");
  assert(session.resetTimeout === undefined, "finishTurn deletes resetTimeout");
  assert(session.messageBuffer.length === before + 1, "finishTurn buffers one event");
  assert(payload.type === "agent_event" && payload.event.sessionUpdate === "turn_ended", "finishTurn buffers turn_ended agent event");
  assert(ws.messages.at(-1)?.type === "turn_ended" && ws.messages.at(-1)?.sessionId === "finish-session" && ws.messages.at(-1)?.stopReason === "end_turn", "finishTurn sends owner turn_ended");
  sessions.delete("finish-session");
}

// A cancellation does not open a second prompt until turn_ended is resolved.
{
  const ws = transport();
  sessions.set("active-session", fakeSession("active-session", ws, {
    turnActive: true,
  }));
  assert(
    (() => {
      try {
        manager.beginPrompt("active-session", "next", ws);
        return false;
      } catch (error) {
        return error instanceof Error && error.message === "session turn already active";
      }
    })(),
    "beginPrompt rejects an active turn",
  );
  sessions.delete("active-session");
}

// Idle eviction cancels permission waits before dropping the session.
{
  const ws = transport();
  let resolved;
  const session = fakeSession("idle-session", ws, {
    lastActivity: Date.now() - 20 * 60 * 1_000,
    orphanedAt: Date.now() - 20 * 60 * 1_000,
    pendingPermissions: new Map([["idle-request", {
      requestId: "idle-request",
      sessionId: "idle-session",
      resolve: (value) => { resolved = value; },
    }]]),
  });
  sessions.set("idle-session", session);
  manager.evictIdle();
  assert(!sessions.has("idle-session"), "evictIdle removes the expired session");
  assert(resolved?.outcome?.outcome === "cancelled", "evictIdle cancels pending permission");
}

// Explicit close also resolves permission waits before deleting the session.
{
  const ws = transport();
  let resolved;
  sessions.set("close-session", fakeSession("close-session", ws, {
    pendingPermissions: new Map([["close-request", {
      requestId: "close-request",
      sessionId: "close-session",
      resolve: (value) => { resolved = value; },
    }]]),
  }));
  await manager.close("close-session", ws);
  assert(!sessions.has("close-session"), "close removes the session");
  assert(resolved?.outcome?.outcome === "cancelled", "close cancels pending permission");
}

manager.stop();
console.log(`Cancel Lifecycle: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
