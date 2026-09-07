import { EventEmitter } from "node:events";
import { sessionManager } from "./dist/session-manager.mjs";
import { handlePermissionResponse } from "./dist/handlers/permission.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) {
    passed += 1;
    console.log(`  ✓ ${message}`);
  } else {
    failed += 1;
    console.error(`  ✗ ${message}`);
  }
}

function createMockWs(name) {
  const socket = new EventEmitter();
  socket.name = name;
  socket.sent = [];
  socket.send = (message) => {
    socket.sent.push(JSON.parse(message));
  };
  return socket;
}

async function main() {
  console.log("Testing Multi-Subscriber Pub/Sub Session Synchronization...");

  const wsA = createMockWs("Client-A (Desktop)");
  const wsB = createMockWs("Client-B (Mobile)");

  // 1. Setup a test session directly
  const sessionId = "pubsub_test_session";
  const mockClient = {
    connected: true,
    loadSession: async () => {},
    resumeSession: async () => {},
  };

  const sess = {
    sessionId,
    ws: wsA,
    ownerTransport: wsA,
    subscribers: new Set([wsA]),
    ownerId: "owner_a",
    client: mockClient,
    cwd: "/test",
    process: { killed: false },
    agent: "opencode",
    pendingPermissions: new Map(),
    terminals: new Map(),
    restartCount: 0,
    toolCallIdMap: new Map(),
    toolContentBytesByCallId: new Map(),
    turnActive: false,
    turnGeneration: 0,
    clientGeneration: 1,
    lastActivity: Date.now(),
    orphanedAt: null,
    messageBuffer: [],
    replayBytes: 0,
  };

  sessionManager.getAllSessions().set(sessionId, sess);

  // 2. Client B attaches to the same session via assertOwner / subscribers
  const sessB = sessionManager.assertOwner(sessionId, wsB);
  assert(sessB.subscribers.has(wsA), "Client A is in subscribers");
  assert(sessB.subscribers.has(wsB), "Client B is auto-added to subscribers");
  assert(sessB.subscribers.size === 2, "Session now has exactly 2 subscribers");

  // 3. Test broadcastToSubscribers
  sessionManager.broadcastToSubscribers(sessionId, {
    type: "agent_event",
    sessionId,
    event: { sessionUpdate: "agent_message_chunk", text: "Hello from Agent" },
  });

  assert(wsA.sent.length === 1 && wsA.sent[0].event.text === "Hello from Agent", "Client A received broadcast event");
  assert(wsB.sent.length === 1 && wsB.sent[0].event.text === "Hello from Agent", "Client B received broadcast event");

  // 4. Test permission resolution broadcasting
  let resolvedValue;
  sess.pendingPermissions.set("req_1", {
    requestId: "req_1",
    sessionId,
    optionIds: ["opt_allow"],
    resolve: (val) => { resolvedValue = val; },
  });

  // Client A resolves the permission
  handlePermissionResponse(wsA, sessionId, "req_1", "selected", "opt_allow");
  assert(resolvedValue?.outcome?.outcome === "selected", "Permission resolved as selected");
  // Client A should not receive permission_resolved (it was the resolver)
  assert(wsA.sent.filter(m => m.type === "permission_resolved").length === 0, "Client A did not receive redundant permission_resolved");
  // Client B MUST receive permission_resolved so its modal is dismissed
  const bResolved = wsB.sent.filter(m => m.type === "permission_resolved");
  assert(bResolved.length === 1 && bResolved[0].requestId === "req_1", "Client B received permission_resolved to dismiss modal");

  // 5. Test partial disconnect: Client A disconnects, Client B remains
  sessionManager.cleanupWsSessions(wsA);
  assert(sess.subscribers.size === 1, "After Client A disconnects, subscribers size is 1");
  assert(sess.subscribers.has(wsB), "Client B remains subscribed");
  assert(sess.orphanedAt === null, "Session is NOT orphaned while Client B is still connected");
  assert(sess.ownerTransport === wsB, "ownerTransport updated to Client B");

  // 6. Test final disconnect: Client B disconnects
  sessionManager.cleanupWsSessions(wsB);
  assert(sess.subscribers.size === 0, "After Client B disconnects, subscribers size is 0");
  assert(sess.orphanedAt !== null, "Session is now orphaned after all clients disconnected");

  // Cleanup
  sessionManager.getAllSessions().delete(sessionId);

  console.log(`\nMulti-subscriber tests: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch(err => {
  console.error("Test failed:", err);
  process.exit(1);
});
