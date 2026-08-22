import { SessionManager, withAcpDeadline } from "./dist/session-manager.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) passed += 1;
  else {
    failed += 1;
    console.error(`FAIL: ${message}`);
  }
}

function deferred() {
  let resolve;
  const promise = new Promise((res) => { resolve = res; });
  return { promise, resolve };
}

function fakeWs() {
  return { send() { } };
}

async function main() {
  let timedOut = false;
  const timeoutStarted = Date.now();
  try {
    await withAcpDeadline("createSession", () => new Promise(() => {}), 10);
  } catch (error) {
    timedOut = error instanceof Error && error.message === "createSession timeout";
  }
  assert(timedOut, "ACP operation deadline rejects a hung operation");
  assert(Date.now() - timeoutStarted < 1000, "ACP operation deadline settles promptly");

  const manager = new SessionManager();
  const originalCreate = manager.getOrCreateInternal;
  const inFlight = deferred();
  manager.getOrCreateInternal = () => inFlight.promise;

  const wsA = fakeWs();
  const wsB = fakeWs();
  const first = manager.getOrCreate(wsA, {});

  // getOrCreate 在返回 await 前同步设置 pendingCreates；WS 消息有序，第二条 Start
  // 进入 server gate 时 hasPendingCreate 必为 true，因此不会发送 start_ack。
  assert(manager.hasPendingCreate(wsA), "first create marks WS as pending");
  const second = manager.getOrCreate(wsA, {});
  assert(manager.hasPendingCreate(wsA), "duplicate create sees the existing pending lock");
  assert(!manager.hasPendingCreate(wsB), "pending lock is isolated per WebSocket");

  inFlight.resolve({ sessionId: "created" });
  await first;
  await second;
  assert(!manager.hasPendingCreate(wsA), "successful create releases the pending lock");

  const failedCreate = new Error("create failed");
  manager.getOrCreateInternal = () => Promise.reject(failedCreate);
  try {
    await manager.getOrCreate(wsA, {});
  } catch (error) {
    assert(error === failedCreate, "create failure reaches the caller");
  }
  assert(!manager.hasPendingCreate(wsA), "failed create releases the pending lock");

  // A timed-out load must release the in-flight marker and dispose the
  // session instead of leaving a permanently locked ACP process in the pool.
  const timeoutManager = new SessionManager(undefined, { acpSessionOperationTimeoutMs: 10 });
  const timeoutWs = fakeWs();
  let destroyed = false;
  const timeoutSession = {
    ws: timeoutWs,
    ownerTransport: timeoutWs,
    ownerId: null,
    client: {
      loadSession: () => new Promise(() => {}),
      destroy: () => { destroyed = true; },
    },
    sessionId: "load-timeout",
    cwd: process.cwd(),
    process: { killed: true },
    agent: "test",
    pendingPermissions: new Map(),
    terminals: new Map(),
    restartCount: 0,
    toolCallIdMap: new Map(),
    toolContentBytesByCallId: new Map(),
    turnActive: false,
    lastActivity: Date.now(),
    orphanedAt: null,
    messageBuffer: [],
    replayBytes: 0,
  };
  timeoutManager.getAllSessions().set("load-timeout", timeoutSession);
  let loadTimedOut = false;
  try {
    await timeoutManager.getOrCreate(timeoutWs, {
      sessionId: "load-timeout",
      mode: "load",
    });
  } catch (error) {
    loadTimedOut = error instanceof Error && error.message === "loadSession timeout";
  }
  assert(loadTimedOut, "hung loadSession is rejected by the ACP deadline");
  assert(destroyed, "timed-out load destroys the unusable ACP client");
  assert(!timeoutManager.getAllSessions().has("load-timeout"), "timed-out load removes the partial session");
  assert(!timeoutManager.hasPendingCreate(timeoutWs), "timed-out load releases the pending create lock");
  timeoutManager.stop();

  manager.getOrCreateInternal = originalCreate;
  manager.stop();
  console.log(`Start gate: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
