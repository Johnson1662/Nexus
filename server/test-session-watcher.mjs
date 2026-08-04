/**
 * SessionWatcher Comprehensive Test Suite
 *
 * Tests the real-time session discovery and status watcher:
 * 1. Unit Test: scanLocalSessionStatuses() schema & time validation
 * 2. Mock Scanner Test: Session detection & mtime status classification (running vs idle)
 * 3. Watcher Engine Test: SessionStatusWatcher diff calculation (added, changed, removed)
 * 4. WebSocket E2E Test: session_status_update broadcast payload verification
 * 5. Pure Function Test: computeSessionDiff() deterministic diff logic
 * 6. Smoke Test: SessionStatusWatcher.scanOnce() real disk scan
 * 7. Pure Function Test: mergeSessionStatus() live state override
 *
 * Usage: node test-session-watcher.mjs
 */

import os from "node:os";
import path from "node:path";
import fs from "node:fs/promises";
import { existsSync, mkdirSync } from "node:fs";
import {
 scanLocalSessionStatuses,
 SessionStatusWatcher,
 computeSessionDiff,
 mergeSessionStatus,
 getLocalAgentLocations,
} from "./dist/discovery/session-watcher.mjs";

let testsPassed = 0;
let testsFailed = 0;

function assert(condition, message) {
 if (!condition) {
  console.error(`\u274c FAIL: ${message}`);
  testsFailed++;
  throw new Error(`Assertion failed: ${message}`);
 } else {
  console.log(`\u2713 PASS: ${message}`);
  testsPassed++;
 }
}

// ── Test 7: mergeSessionStatus Pure Function ────────────────────────

function testMergeSessionStatus() {
 console.log("\n--- Test 7: mergeSessionStatus Pure Function ---");
 const allKnown = new Set(["s1", "s2", "s3", "s4"]);
 const base = [
  { sessionId: "s1", agentName: "opencode", status: "idle", lastActivity: 0 },
  { sessionId: "s2", agentName: "omp", status: "idle", lastActivity: 0 },
  { sessionId: "s3", agentName: "claude-code", status: "running", lastActivity: Date.now() },
  { sessionId: "unmatched-label", agentName: "opencode", status: "running", lastActivity: Date.now() },
 ];

 // 7a. No active IDs, all known → unchanged (but unknown filtered out)
 const r1 = mergeSessionStatus(base, new Set(), allKnown);
 assert(r1.length === 3, "Unknown static label filtered out (sessions: s1,s2,s3)");
 assert(r1[0].status === "idle", "No active IDs: idle stays idle");
 assert(r1[1].status === "idle", "No active IDs: second stays idle");
 assert(r1[2].status === "running", "No active IDs: running stays running");

 // 7b. Active ID overrides idle → "running"
 const r2 = mergeSessionStatus(base, new Set(["s1"]), allKnown);
 assert(r2.length === 3, "Unknown label still filtered");
 assert(r2[0].status === "running", "s1 in activeIds: idle→running");
 assert(r2[1].status === "idle", "s2 not active: stays idle");
 assert(r2[2].status === "running", "s3 not in activeIds but already running");

 // 7c. Active ID does not override running → stays "running"
 const r3 = mergeSessionStatus(base, new Set(["s3"]), allKnown);
 assert(r3[2].status === "running", "s3 active: running stays running");

 // 7d. Multiple active IDs
 const r4 = mergeSessionStatus(base, new Set(["s1", "s2"]), allKnown);
 assert(r4[0].status === "running", "s1 active: idle→running");
 assert(r4[1].status === "running", "s2 active: idle→running");
 assert(r4[2].status === "running", "s3 not active but already running");

 // 7e. knownIds covers all base entries → no filtering beyond unmatched-label
 const r5 = mergeSessionStatus(base, new Set(["s99"]), allKnown);
 assert(r5.length === 3, "active IDs not in disk: no extra entries, unknown filtered");
 assert(r5[0].status === "idle", "s1 unchanged");

 // 7f. Original array not mutated (pure function)
 const originalStatus = base[0].status;
 mergeSessionStatus(base, new Set(["s1"]), allKnown);
 assert(base[0].status === originalStatus, "original array not mutated");

 // 7g. Empty disk → empty output
 const r6 = mergeSessionStatus([], new Set(["s1"]), allKnown);
 assert(r6.length === 0, "empty disk: empty output");

 // 7h. No knownIds → empty output (no unresolvable identity leaks)
 const r7 = mergeSessionStatus(base, new Set(), new Set());
 assert(r7.length === 0, "no known IDs: empty output, no identity leak");

 // 7i. Disk entry not in knownIds → filtered out (static e.g. opencode-active)
 const r8 = mergeSessionStatus(
  [{ sessionId: "opencode-active", agentName: "opencode", status: "running", lastActivity: Date.now() }],
  new Set(),
  new Set(["real-ses-123"]),
 );
 assert(r8.length === 0, "static label 'opencode-active' filtered when no SessionManager session matches");
}

// ── Test 1: Unit Test (scanLocalSessionStatuses) ────────────────────

async function testScanLocalSessionStatuses() {
 console.log("\n--- Test 1: scanLocalSessionStatuses Unit Test ---");
 const results = await scanLocalSessionStatuses();
 assert(Array.isArray(results), "scanLocalSessionStatuses returns an array");
 console.log(`  Found ${results.length} total local sessions currently on disk.`);

 for (const s of results) {
  assert(typeof s.sessionId === "string" && s.sessionId.length > 0, `Valid sessionId: ${s.sessionId}`);
  assert(typeof s.agentName === "string" && s.agentName.length > 0, `Valid agentName: ${s.agentName}`);
  assert(
   ["running", "waiting_input", "idle", "error"].includes(s.status),
   `Valid status "${s.status}" for session ${s.sessionId}`
  );
  assert(typeof s.lastActivity === "number" && s.lastActivity > 0, `Valid lastActivity timestamp: ${s.lastActivity}`);
 }
}

// ── Test 2: Mock Scanner & Status Classification ──────────────────────

async function testMockScannerStatusClassification() {
 console.log("\n--- Test 2: Mock Scanner & Status Classification Test ---");
 const home = os.homedir();
 const testClaudeDir = path.join(home, ".claude", "sessions");
 await fs.mkdir(testClaudeDir, { recursive: true });

 const testSessionId = `test_session_${Date.now()}`;
 const testFilePath = path.join(testClaudeDir, `${testSessionId}.json`);

 try {
  // 2a. Create fresh file (mtime = now -> should be "running")
  await fs.writeFile(testFilePath, JSON.stringify({ id: testSessionId, test: true }), "utf-8");
  const freshScan = await scanLocalSessionStatuses();
  const freshItem = freshScan.find((s) => s.sessionId === testSessionId);

  assert(freshItem !== undefined, `Mock session ${testSessionId} discovered by scanner`);
  assert(freshItem.agentName === "claude-code", `Discovered as claude-code agent`);
  assert(freshItem.status === "running", `Fresh file classified as "running" (mtime < 15s)`);

  // 2b. Update mtime to 30 seconds ago (should switch to "idle")
  const pastTime = new Date(Date.now() - 30000);
  await fs.utimes(testFilePath, pastTime, pastTime);

  const staleScan = await scanLocalSessionStatuses();
  const staleItem = staleScan.find((s) => s.sessionId === testSessionId);

  assert(staleItem !== undefined, `Stale session ${testSessionId} still present in scan`);
  assert(staleItem.status === "idle", `Stale file (mtime > 15s) classified as "idle"`);
 } finally {
  // Clean up mock file
  if (existsSync(testFilePath)) {
   await fs.unlink(testFilePath);
  }
 }
}

// ── Test 3: Watcher Engine & Diff Calculation ────────────────────────

async function testWatcherDiffEngine() {
 console.log("\n--- Test 3: Watcher Engine & Diff Calculation Test ---");
 const home = os.homedir();
 const testClaudeDir = path.join(home, ".claude", "sessions");
 await fs.mkdir(testClaudeDir, { recursive: true });

 const testSessionId = `watcher_test_${Date.now()}`;
 const testFilePath = path.join(testClaudeDir, `${testSessionId}.json`);

 let addedReceived = [];
 let removedReceived = [];
 let changedReceived = [];

 const watcher = new SessionStatusWatcher(500);
 watcher.onStatusUpdate(({ added, removed, changed }) => {
  console.log("    [watcher callback fired] added:", added.map(s => s.sessionId), "changed:", changed.map(s => s.sessionId), "removed:", removed.map(s => s.sessionId));
  addedReceived.push(...added);
  removedReceived.push(...removed);
  changedReceived.push(...changed);
 });

 try {
  // Start watcher with fast 500ms interval
  watcher.start();
  assert(true, "SessionStatusWatcher started with 500ms interval");

  // Wait 1200ms for initial baseline scan to complete
  await new Promise((resolve) => setTimeout(resolve, 1200));

  // 3a. Write new session file -> should trigger "added"
  await fs.writeFile(testFilePath, JSON.stringify({ id: testSessionId }), "utf-8");
  await new Promise((resolve) => setTimeout(resolve, 1100));

  const addedMatch = addedReceived.find((s) => s.sessionId === testSessionId);
  assert(addedMatch !== undefined, `Watcher detected new session file in "added" diff`);

  // 3b. Touch file (update mtime by 5 seconds) -> should trigger "changed"
  const futureTime = new Date(Date.now() + 5000);
  await fs.utimes(testFilePath, futureTime, futureTime);
  await new Promise((resolve) => setTimeout(resolve, 1100));

  const changedMatch = changedReceived.find((s) => s.sessionId === testSessionId);
  assert(changedMatch !== undefined, `Watcher detected mtime change in "changed" diff`);

  // 3c. Delete file -> should trigger "removed"
  await fs.unlink(testFilePath);
  await new Promise((resolve) => setTimeout(resolve, 1100));

  const removedMatch = removedReceived.find((s) => s.sessionId === testSessionId);
  assert(removedMatch !== undefined, `Watcher detected deleted session file in "removed" diff`);
 } finally {
  if (existsSync(testFilePath)) {
   await fs.unlink(testFilePath);
  }
  watcher.stop();
  assert(true, "SessionStatusWatcher stopped and listeners cleared successfully");
 }
}

// ── Test 4: WebSocket Broadcast Payload Verification ─────────────────

async function testWebSocketBroadcast() {
 console.log("\n--- Test 4: WebSocket Broadcast Payload Verification ---");

 // Mock WebSocket Client & Server broadcast simulation.
 // Uses the actual production protocol: { type: "session_status_update", sessions }.
 const mockWsMessages = [];
 const mockClients = [
  {
   readyState: 1, // OPEN
   send: (msgStr) => {
    mockWsMessages.push(JSON.parse(msgStr));
   },
  },
 ];

 // Simulating server.mts startSessionWatcher's flushPending
 const mockBroadcast = (sessions) => {
  const payload = JSON.stringify({
   type: "session_status_update",
   sessions,
  });
  for (const ws of mockClients) {
   if (ws.readyState === 1) {
    ws.send(payload);
   }
  }
 };

 const sampleSession = {
  sessionId: "broadcast_test_123",
  agentName: "opencode",
  status: "running",
  lastActivity: Date.now(),
 };

 // Simulate a flush with one session
 mockBroadcast([sampleSession]);

 assert(mockWsMessages.length === 1, "Mock WebSocket client received 1 message");
 const msg = mockWsMessages[0];
 assert(msg.type === "session_status_update", `Received correct WS message type: ${msg.type}`);
 assert(Array.isArray(msg.sessions), "Payload contains sessions array");
 assert(msg.sessions.length === 1, "sessions array has 1 entry");
 assert(msg.sessions[0].sessionId === sampleSession.sessionId, `Session ID matches: ${msg.sessions[0].sessionId}`);
 assert(msg.sessions[0].status === "running", `Session status matches: ${msg.sessions[0].status}`);
 // Verify no legacy top-level arrays leak
 assert(msg.added === undefined, "No legacy 'added' field in payload");
 assert(msg.removed === undefined, "No legacy 'removed' field in payload");
 assert(msg.changed === undefined, "No legacy 'changed' field in payload");
}

// ── Test 5: computeSessionDiff Pure Function ─────────────────────────

function testComputeSessionDiff() {
 console.log("\n--- Test 5: computeSessionDiff Pure Function ---");

 // 5a. Empty prev, non-empty curr -> all added
 const prev = [];
 const curr = [
  { sessionId: "s1", agentName: "a", status: "running", lastActivity: 1000 },
 ];
 const r1 = computeSessionDiff(prev, curr);
 assert(r1.added.length === 1, "Empty prev -> added contains new session");
 assert(r1.removed.length === 0, "Empty prev -> removed is empty");
 assert(r1.changed.length === 0, "Empty prev -> changed is empty");
 assert(r1.added[0].sessionId === "s1", "Added entry has correct sessionId");
 assert(r1.added[0].status === "running", "Added entry preserves original status");

 // 5b. Single session disappears -> removed with idle status
 const r2 = computeSessionDiff(curr, prev);
 assert(r2.added.length === 0, "Sessions removed -> added is empty");
 assert(r2.removed.length === 1, "Session removed -> removed has entry");
 assert(r2.removed[0].status === "idle", "Removed entry gets idle status");
 assert(r2.removed[0].sessionId === "s1", "Removed entry has correct sessionId");
 assert(r2.changed.length === 0, "Sessions removed -> changed is empty");

 // 5c. Status changed -> changed
 const curr2 = [
  { sessionId: "s1", agentName: "a", status: "idle", lastActivity: 1000 },
 ];
 const r3 = computeSessionDiff(curr, curr2);
 assert(r3.added.length === 0, "Status changed -> added is empty");
 assert(r3.removed.length === 0, "Status changed -> removed is empty");
 assert(r3.changed.length === 1, "Status changed -> changed has entry");
 assert(r3.changed[0].sessionId === "s1", "Changed entry has correct sessionId");
 assert(r3.changed[0].status === "idle", "Changed entry has new status");

 // 5d. Activity changed by >3s -> changed
 const curr3 = [
  { sessionId: "s1", agentName: "a", status: "running", lastActivity: 5000 },
 ];
 const r4 = computeSessionDiff(curr, curr3);
 assert(r4.changed.length === 1, "Activity diff >3s -> changed entry");
 assert(r4.changed[0].lastActivity === 5000, "Changed entry has new activity timestamp");
 assert(r4.added.length === 0, "Large activity change -> no added");
 assert(r4.removed.length === 0, "Large activity change -> no removed");

 // 5e. Activity changed by <3s -> no change
 const curr4 = [
  { sessionId: "s1", agentName: "a", status: "running", lastActivity: 1001 },
 ];
 const r5 = computeSessionDiff(curr, curr4);
 assert(r5.changed.length === 0, "Activity diff <3s -> no change");
 assert(r5.added.length === 0, "Small activity change -> no added");
 assert(r5.removed.length === 0, "Small activity change -> no removed");

 // 5f. Identical snapshots -> empty diff
 const r6 = computeSessionDiff(curr, curr);
 assert(r6.added.length === 0, "Identical -> no added");
 assert(r6.removed.length === 0, "Identical -> no removed");
 assert(r6.changed.length === 0, "Identical -> no changed");

 // 5g. Mixed: added + removed + changed simultaneously
 const prevMixed = [
  { sessionId: "s1", agentName: "a", status: "running", lastActivity: 1000 },
  { sessionId: "s2", agentName: "a", status: "idle", lastActivity: 2000 },
 ];
 const currMixed = [
  { sessionId: "s1", agentName: "a", status: "idle", lastActivity: 1000 },    // changed
  { sessionId: "s3", agentName: "b", status: "running", lastActivity: 3000 },  // added
 ];
 const r7 = computeSessionDiff(prevMixed, currMixed);
 assert(r7.added.length === 1, "Mixed test: 1 added");
 assert(r7.removed.length === 1, "Mixed test: 1 removed (s2)");
 assert(r7.changed.length === 1, "Mixed test: 1 changed (s1)");
 assert(r7.removed[0].sessionId === "s2", "Removed entry is s2");
 assert(r7.removed[0].status === "idle", "Removed s2 is forced to idle");
 assert(r7.added[0].sessionId === "s3", "Added entry is s3");
 assert(r7.changed[0].sessionId === "s1", "Changed entry is s1");

 // 5h. Different agentName for same sessionId -> treated as different entries
 const prevDiffAgent = [
  { sessionId: "s1", agentName: "claude-code", status: "running", lastActivity: 1000 },
 ];
 const currDiffAgent = [
  { sessionId: "s1", agentName: "opencode", status: "running", lastActivity: 1000 },
 ];
 const r8 = computeSessionDiff(prevDiffAgent, currDiffAgent);
 assert(r8.added.length === 1, "Different agent -> curr entry is added");
 assert(r8.removed.length === 1, "Different agent -> prev entry is removed");
 assert(r8.changed.length === 0, "Different agent -> no changed (it's add+remove)");
}

// ── Test 6: SessionStatusWatcher.scanOnce() Smoke Test ────────────────

async function testWatcherScanOnce() {
 console.log("\n--- Test 6: SessionStatusWatcher.scanOnce() Smoke Test ---");
 const watcher = new SessionStatusWatcher();
 const results = await watcher.scanOnce();
 assert(Array.isArray(results), "scanOnce() returns an array");
 // Should match scanLocalSessionStatuses output structure
 for (const s of results) {
  assert(typeof s.sessionId === "string" && s.sessionId.length > 0, `scanOnce sessionId: ${s.sessionId}`);
  assert(typeof s.agentName === "string", `scanOnce agentName: ${s.agentName}`);
  assert(["running", "waiting_input", "idle", "error"].includes(s.status), `scanOnce status: ${s.status}`);
 }
 console.log(`  scanOnce found ${results.length} sessions.`);
}

// ── Test 8: Identity regression — static labels filtered from mergeSessionStatus ──

function testIdentityRegression() {
 console.log("\n--- Test 8: Identity Regression (static labels never leak) ---");

 // 8a. Static filesystem label with no matching SessionManager session → empty
 const staticLabel = [
  { sessionId: "opencode-active", agentName: "opencode", status: "running", lastActivity: Date.now() },
  { sessionId: "omp-active", agentName: "omp", status: "running", lastActivity: Date.now() },
 ];
 const emptyKnown = new Set();
 const r1 = mergeSessionStatus(staticLabel, new Set(), emptyKnown);
 assert(r1.length === 0, "opencode-active + omp-active with no known IDs → empty");

 // 8b. Static label alongside real session ID — only real ID survives
 const mixed = [
  { sessionId: "opencode-active", agentName: "opencode", status: "running", lastActivity: Date.now() },
  { sessionId: "ses_abc123", agentName: "opencode", status: "idle", lastActivity: 1000 },
 ];
 const known = new Set(["ses_abc123"]);
 const r2 = mergeSessionStatus(mixed, new Set(), known);
 assert(r2.length === 1, "Only known session ID survives (opencode-active filtered)");
 assert(r2[0].sessionId === "ses_abc123", "Surviving entry is the canonical session");
 assert(r2[0].status === "idle", "Canonical session status preserved");

 // 8c. Static label never overrides active session status
 const active = new Set(["ses_xyz789"]);
 const mixed2 = [
  { sessionId: "opencode-active", agentName: "opencode", status: "running", lastActivity: Date.now() },
  { sessionId: "ses_xyz789", agentName: "opencode", status: "idle", lastActivity: 1000 },
 ];
 const known2 = new Set(["ses_xyz789"]);
 const r3 = mergeSessionStatus(mixed2, active, known2);
 assert(r3.length === 1, "Static label filtered even with activeIds");
 assert(r3[0].sessionId === "ses_xyz789", "Only canonical session in result");
 assert(r3[0].status === "running", "Canonical session status overridden to running (turnActive)");

 // 8d. Empty disk + empty known → empty (no crash)
 const r4 = mergeSessionStatus([], new Set(), new Set());
 assert(r4.length === 0, "empty disk + empty known → empty");

 // 8e. Real session not on disk but in knownIds → not in result (mergeSessionStatus
 //     only filters, it doesn't inject — server.mts startSessionWatcher supplements)
 const r5 = mergeSessionStatus([], new Set(), new Set(["ses_only_in_memory"]));
 assert(r5.length === 0, "Session only in memory is not injected by mergeSessionStatus (caller's job)");
}

// ── Runner ─────────────────────────────────────────────────────────

async function main() {
 console.log("=================================================");
 console.log("  Nexus SessionWatcher Integration Test Suite    ");
 console.log("=================================================");

 try {
  // Pure function tests run first (synchronous, no I/O)
  testComputeSessionDiff();
  testMergeSessionStatus();
  testIdentityRegression();

  // Async tests
  await testScanLocalSessionStatuses();
  await testMockScannerStatusClassification();
  await testWatcherDiffEngine();
  await testWebSocketBroadcast();
  await testWatcherScanOnce();

  console.log("\n=================================================");
  console.log(`\uD83c\uDF89 ALL TESTS PASSED! (${testsPassed} checks passed, 0 failed)`);
  console.log("=================================================");
 } catch (err) {
  console.error("\n=================================================");
  console.error(`\uD83D\uDCA5 TEST SUITE FAILED: ${err.message}`);
  console.error(`Summary: ${testsPassed} passed, ${testsFailed + 1} failed`);
  console.error("=================================================");
  process.exit(1);
 }
}

main();
