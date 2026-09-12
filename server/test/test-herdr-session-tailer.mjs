import assert from "node:assert";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { HerdrSessionTailer, HerdrTailerRegistry } from "../dist/discovery/herdr-session-tailer.mjs";

console.log("=== Testing herdr-session-tailer ===");

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "nexus-tailer-test-"));
const testFile = path.join(tmpDir, "test-session.jsonl");

// Initialize empty file
fs.writeFileSync(testFile, "");

const mockEvents = [];
const mockWs = {
  readyState: 1,
  send: (payload) => {
    mockEvents.push(JSON.parse(payload));
  },
};

const tailer = HerdrTailerRegistry.getOrCreate(testFile, "test-session-1", "w1:p1", 0);
tailer.subscribe(mockWs);

// 1. Write an incomplete JSON line (split across two writes)
const completeJson = JSON.stringify({
  type: "message",
  message: {
    role: "assistant",
    content: [{ type: "thinking", thinking: "Partial write test" }],
  },
}) + "\n";

const half = Math.floor(completeJson.length / 2);
const part1 = completeJson.slice(0, half);
const part2 = completeJson.slice(half);

fs.appendFileSync(testFile, part1);

// Wait 100ms: tailer should not emit any corrupted event from part 1
await new Promise((r) => setTimeout(r, 100));
assert.strictEqual(mockEvents.length, 0, "Partial line should not emit premature events");

// Now append part 2 (which finishes the line)
fs.appendFileSync(testFile, part2);

// Wait 600ms for tailer to read and process
await new Promise((r) => setTimeout(r, 600));

assert.strictEqual(mockEvents.length, 1, "Completed line should emit 1 event");
assert.strictEqual(mockEvents[0].type, "agent_event");
assert.strictEqual(mockEvents[0].event.sessionUpdate, "agent_thought_chunk");
assert.strictEqual(mockEvents[0].event.content.text, "Partial write test");

// 2. Test user prompt deduplication
mockEvents.length = 0;
tailer.setLastInjectedPrompt("Hello from mobile", mockWs);

const userLine = JSON.stringify({
  type: "message",
  message: {
    role: "user",
    content: [{ type: "text", text: "Hello from mobile" }],
  },
}) + "\n";

fs.appendFileSync(testFile, userLine);

await new Promise((r) => setTimeout(r, 600));

// The sender ws should NOT receive the echoed user message chunk
assert.strictEqual(mockEvents.length, 0, "Echoed user prompt should be suppressed for sender ws");

// 3. Cleanup test
tailer.unsubscribe(mockWs);
assert.strictEqual(tailer.hasSubscribers(), false);
HerdrTailerRegistry.cleanupAll();

// Clean temp directory
fs.rmSync(tmpDir, { recursive: true, force: true });

console.log("ALL TESTS PASSED for herdr-session-tailer!");
