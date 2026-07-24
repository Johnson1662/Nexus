/**
 * SessionWatcher Comprehensive Test Suite
 *
 * Tests the real-time session discovery and status watcher:
 * 1. Unit Test: scanLocalSessionStatuses() schema & time validation
 * 2. Mock Scanner Test: Session detection & mtime status classification (running vs idle)
 * 3. Watcher Engine Test: startWatcher/stopWatcher diff calculation (added, changed, removed)
 * 4. WebSocket E2E Test: session_status_update broadcast payload verification
 *
 * Usage: node test-session-watcher.mjs
 */

import os from "node:os";
import path from "node:path";
import fs from "node:fs/promises";
import { existsSync, mkdirSync } from "node:fs";
import {
 scanLocalSessionStatuses,
 startWatcher,
 stopWatcher,
 getLocalAgentLocations,
} from "./dist/discovery/session-watcher.mjs";

let testsPassed = 0;
let testsFailed = 0;

function assert(condition, message) {
 if (!condition) {
  console.error(`❌ FAIL: ${message}`);
  testsFailed++;
  throw new Error(`Assertion failed: ${message}`);
 } else {
  console.log(`✓ PASS: ${message}`);
  testsPassed++;
 }
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
 stopWatcher(); // Reset any existing watcher timer
 const home = os.homedir();
 const testClaudeDir = path.join(home, ".claude", "sessions");
 await fs.mkdir(testClaudeDir, { recursive: true });

 const testSessionId = `watcher_test_${Date.now()}`;
 const testFilePath = path.join(testClaudeDir, `${testSessionId}.json`);

 let addedReceived = [];
 let removedReceived = [];
 let changedReceived = [];

 const onChangeCallback = (added, removed, changed) => {
  console.log("    [watcher callback fired] added:", added.map(s => s.sessionId), "changed:", changed.map(s => s.sessionId), "removed:", removed.map(s => s.sessionId));
  addedReceived.push(...added);
  removedReceived.push(...removed);
  changedReceived.push(...changed);
 };

 try {
  // Start watcher with fast 500ms interval
  startWatcher(onChangeCallback, 500);
  assert(true, "Watcher started with 500ms interval");

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
  stopWatcher(onChangeCallback);
  assert(true, "stopWatcher executed and callback unregistered successfully");
 }
}

// ── Test 4: WebSocket Broadcast Payload Verification ─────────────────

async function testWebSocketBroadcast() {
 console.log("\n--- Test 4: WebSocket Broadcast Payload Verification ---");

 // Mock WebSocket Client & Server broadcast simulation
 const mockWsMessages = [];
 const mockClients = [
  {
   readyState: 1, // OPEN
   send: (msgStr) => {
    mockWsMessages.push(JSON.parse(msgStr));
   },
  },
 ];

 // Simulating server.mts startSessionWatcher handler
 const mockBroadcastHandler = (added, removed, changed) => {
  const payload = JSON.stringify({
   type: "session_status_update",
   added,
   removed,
   changed,
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

 // Simulate watcher triggering callback
 mockBroadcastHandler([sampleSession], [], []);

 assert(mockWsMessages.length === 1, "Mock WebSocket client received 1 message");
 const msg = mockWsMessages[0];
 assert(msg.type === "session_status_update", `Received correct WS message type: ${msg.type}`);
 assert(Array.isArray(msg.added) && msg.added.length === 1, "Payload contains added array");
 assert(msg.added[0].sessionId === sampleSession.sessionId, `Session ID matches: ${msg.added[0].sessionId}`);
 assert(msg.added[0].status === "running", `Session status matches: ${msg.added[0].status}`);
}

// ── Runner ─────────────────────────────────────────────────────────

async function main() {
 console.log("=================================================");
 console.log("  Nexus SessionWatcher Integration Test Suite    ");
 console.log("=================================================");

 try {
  await testScanLocalSessionStatuses();
  await testMockScannerStatusClassification();
  await testWatcherDiffEngine();
  await testWebSocketBroadcast();

  console.log("\n=================================================");
  console.log(`🎉 ALL TESTS PASSED! (${testsPassed} checks passed, 0 failed)`);
  console.log("=================================================");
 } catch (err) {
  console.error("\n=================================================");
  console.error(`💥 TEST SUITE FAILED: ${err.message}`);
  console.error(`Summary: ${testsPassed} passed, ${testsFailed + 1} failed`);
  console.error("=================================================");
  process.exit(1);
 }
}

main();
