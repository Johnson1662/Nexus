import assert from "node:assert";
import {
  extractText,
  convertJsonlRecordToAcpUpdates,
  convertJsonlLinesToAcpUpdates,
  readSessionJsonlToAcpUpdates,
} from "./dist/discovery/herdr-acp-converter.mjs";

console.log("=== Testing herdr-acp-converter ===");

// 1. Test extractText
assert.strictEqual(extractText("hello world"), "hello world");
assert.strictEqual(extractText([{ type: "text", text: "part 1 " }, { type: "text", text: "part 2" }]), "part 1 part 2");
assert.strictEqual(extractText({ type: "text", text: "single block" }), "single block");
assert.strictEqual(extractText(null), "");

// 2. Test user message
const userRecord = {
  type: "message",
  message: {
    role: "user",
    content: [{ type: "text", text: "Evaluate wiki home page" }],
  },
};
const userUpdates = convertJsonlRecordToAcpUpdates(userRecord);
assert.strictEqual(userUpdates.length, 1);
assert.strictEqual(userUpdates[0].sessionUpdate, "user_message_chunk");
assert.strictEqual(userUpdates[0].content.text, "Evaluate wiki home page");

// 3. Test assistant message with thinking, toolCall, and text
const assistantRecord = {
  type: "message",
  message: {
    role: "assistant",
    content: [
      { type: "thinking", thinking: "I should check the files." },
      {
        type: "toolCall",
        id: "call_123",
        name: "eval",
        arguments: { code: "console.log(1)" },
      },
      { type: "text", text: "Here is the result." },
    ],
  },
};
const assistantUpdates = convertJsonlRecordToAcpUpdates(assistantRecord);
assert.strictEqual(assistantUpdates.length, 3);
assert.strictEqual(assistantUpdates[0].sessionUpdate, "agent_thought_chunk");
assert.strictEqual(assistantUpdates[0].content.text, "I should check the files.");
assert.strictEqual(assistantUpdates[1].sessionUpdate, "tool_call");
assert.strictEqual(assistantUpdates[1].toolCallId, "call_123");
assert.strictEqual(assistantUpdates[1].title, "eval");
assert.strictEqual(assistantUpdates[2].sessionUpdate, "agent_message_chunk");
assert.strictEqual(assistantUpdates[2].content.text, "Here is the result.");

// 4. Test toolResult (success and error)
const toolResultSuccess = {
  type: "message",
  message: {
    role: "toolResult",
    toolCallId: "call_123",
    isError: false,
    content: [{ type: "text", text: "1\n" }],
  },
};
const toolUpdatesSuccess = convertJsonlRecordToAcpUpdates(toolResultSuccess);
assert.strictEqual(toolUpdatesSuccess.length, 1);
assert.strictEqual(toolUpdatesSuccess[0].sessionUpdate, "tool_call_update");
assert.strictEqual(toolUpdatesSuccess[0].toolCallId, "call_123");
assert.strictEqual(toolUpdatesSuccess[0].status, "completed");
assert.strictEqual(toolUpdatesSuccess[0].content[0].content.text, "1\n");

const toolResultError = {
  type: "message",
  message: {
    role: "toolResult",
    toolCallId: "call_456",
    isError: true,
    content: [{ type: "text", text: "Command failed: exit 1" }],
  },
};
const toolUpdatesError = convertJsonlRecordToAcpUpdates(toolResultError);
assert.strictEqual(toolUpdatesError[0].status, "failed");

// 5. Test real session file
const realSession = "/home/johnson/.omp/agent/sessions/--media-johnson-Data-Development-iGEM--/2026-09-07T07-43-56-077Z_01a07ad2-e2ad-766f-ae52-5029b02dc059.jsonl";
const fileUpdates = await readSessionJsonlToAcpUpdates(realSession);
console.log(`Successfully parsed real session: ${fileUpdates.length} ACP events loaded`);
assert(fileUpdates.length > 50, "Expected at least 50 events from real session");

console.log("ALL TESTS PASSED for herdr-acp-converter!");
