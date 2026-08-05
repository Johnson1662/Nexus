import { SessionManager } from "./dist/session-manager.mjs";

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

  manager.getOrCreateInternal = originalCreate;
  manager.stop();
  console.log(`Start gate: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
