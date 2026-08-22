import { Buffer } from "node:buffer";

import { sessionManager } from "./dist/session-manager.mjs";
import {
  boundFileEventPayload,
  boundAgentEventPayload,
  countToolContentBytes,
  MAX_AGENT_EVENT_BYTES,
  MAX_FILE_EVENT_BYTES,
  MAX_TOOL_CONTENT_BYTES,
  truncateUtf8,
} from "./dist/payload-budget.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) passed += 1;
  else {
    failed += 1;
    console.error(`FAIL: ${message}`);
  }
}

function fakeTransport() {
  return { send() {} };
}

const sessions = sessionManager.getAllSessions();
const sessionId = "payload-budget-test";
const session = {
  ws: fakeTransport(),
  ownerTransport: null,
  messageBuffer: [],
  replayBytes: 0,
  toolContentBytesByCallId: new Map(),
};
sessions.set(sessionId, session);

try {
  const result = sessionManager.bufferAgentEvent(sessionId, {
    type: "agent_event",
    sessionId,
    event: {
      sessionUpdate: "tool_call_update",
      toolCallContent: [{
        type: "content",
        content: { type: "text", text: "字".repeat(3 * 1024 * 1024) },
      }],
    },
  });
  const entry = session.messageBuffer[0];
  const serialized = entry?.payload ?? "";
  const parsed = JSON.parse(serialized);
  assert(Buffer.byteLength(serialized, "utf8") <= 512 * 1024, "single oversized event stays below the 512KB entry cap");
  assert(entry?.payloadBytes === Buffer.byteLength(serialized, "utf8"), "payload byte accounting uses UTF-8 bytes");
  assert(parsed.event?.truncated === true, "oversized event is explicitly marked truncated");
  assert(parsed.event?.originalBytes > 3 * 1024 * 1024, "truncation metadata preserves the original UTF-8 size");
  assert(result?.messageId === entry?.messageId, "bounded replay payload keeps its message id");
  assert(session.replayBytes <= 2 * 1024 * 1024, "single oversized event cannot bypass the 2MB replay budget");

  const toolEvent = {
    type: "agent_event",
    sessionId,
    event: {
      sessionUpdate: "tool_call_update",
      toolCallId: "tool-large",
      status: "in_progress",
      toolCallContent: [{
        type: "content",
        content: { type: "text", text: "界".repeat(700 * 1024) },
      }],
    },
  };
  const boundedTool = sessionManager.bufferAgentEvent(sessionId, toolEvent);
  const parsedTool = JSON.parse(session.messageBuffer.at(-1).payload);
  assert(parsedTool.event?.sessionUpdate === "tool_call_update", "large tool event keeps sessionUpdate");
  assert(parsedTool.event?.toolCallId === "tool-large", "large tool event keeps toolCallId");
  assert(parsedTool.event?.status === "in_progress", "large tool event keeps status");
  assert(Array.isArray(parsedTool.event?.toolCallContent), "large tool event keeps content blocks");
  assert(parsedTool.event?.toolCallContent[0]?.content?.type === "text", "large tool event keeps block type");
  assert(countToolContentBytes(parsedTool) <= MAX_TOOL_CONTENT_BYTES, "large tool event text stays below the cumulative tool cap");
  assert(session.messageBuffer.at(-1)?.payloadBytes <= MAX_AGENT_EVENT_BYTES, "bounded tool result stays below the event cap");

  const hugeBlockArray = boundAgentEventPayload({
    type: "agent_event",
    sessionId,
    event: {
      sessionUpdate: "tool_call_update",
      toolCallId: "huge-block-array",
      toolCallContent: Array.from({ length: 100_000 }, () => ({
        type: "content",
        content: { type: "text", text: "x" },
      })),
    },
  });
  const hugeBlockPayload = JSON.parse(hugeBlockArray.payload);
  assert(hugeBlockArray.payloadBytes <= MAX_AGENT_EVENT_BYTES, "last-resort event shape stays below the hard cap");
  assert(hugeBlockPayload.event?.structureTruncated === true, "last-resort event shape marks structural truncation");
  assert(hugeBlockPayload.event?.toolCallContent?.length <= 5_000, "bounded event shape caps content blocks");

  const wideStructure = boundAgentEventPayload({
    type: "agent_event",
    sessionId,
    event: {
      sessionUpdate: "agent_message_chunk",
      metadata: Array.from({ length: 6_000 }, (_, index) => ({ index, value: "x" })),
    },
  });
  const wideStructurePayload = JSON.parse(wideStructure.payload);
  assert(wideStructurePayload.event?.metadata?.length <= 5_000, "generic payload structures stop after the entry cap");
  assert(wideStructurePayload.event?.structureTruncated === true, "generic payload structures mark structural truncation");

  const diffPayload = boundFileEventPayload({
    type: "file_diff",
    path: "src/巨大文件.ts",
    diff: "😀旧文本".repeat(90 * 1024) + "\n---\n" + "新文本😀".repeat(90 * 1024),
  });
  const parsedDiff = JSON.parse(diffPayload.payload);
  assert(diffPayload.payloadBytes <= MAX_FILE_EVENT_BYTES, "large file diff stays below the file event cap");
  assert(parsedDiff.type === "file_diff", "large file diff keeps top-level type");
  assert(parsedDiff.path === "src/巨大文件.ts", "large file diff keeps top-level path");
  assert(typeof parsedDiff.diff === "string" && parsedDiff.diff.length > 0, "large file diff keeps top-level diff");
  assert(parsedDiff.truncated === true, "large file diff is explicitly marked truncated");

  const contentPayload = boundFileEventPayload({
    type: "file_content",
    path: "README.md",
    content: "中文🙂".repeat(180 * 1024),
  });
  const parsedContent = JSON.parse(contentPayload.payload);
  assert(contentPayload.payloadBytes <= MAX_FILE_EVENT_BYTES, "large file content stays below the file event cap");
  assert(parsedContent.type === "file_content", "large file content keeps top-level type");
  assert(parsedContent.path === "README.md", "large file content keeps top-level path");
  assert(typeof parsedContent.content === "string" && parsedContent.content.length > 0, "large file content keeps top-level content");
  assert(parsedContent.truncated === true, "large file content is explicitly marked truncated");

  const unicode = truncateUtf8("😀中文A", 7);
  assert(unicode.retainedBytes === 7, "UTF-8 truncation uses byte length");
  assert(unicode.text === "😀中", "UTF-8 truncation does not split a code point");

  const cumulativeId = "tool-cumulative";
  for (let index = 0; index < 100; index += 1) {
    sessionManager.bufferAgentEvent(sessionId, {
      type: "agent_event",
      sessionId,
      event: {
        sessionUpdate: "tool_call_update",
        toolCallId: cumulativeId,
        status: "in_progress",
        toolCallContent: [{ type: "content", content: { type: "text", text: "x".repeat(10 * 1024) } }],
      },
    });
  }
  assert(
    session.toolContentBytesByCallId.get(cumulativeId) <= MAX_TOOL_CONTENT_BYTES,
    "repeated tool updates stay below the cumulative tool cap",
  );
  const cumulativeTextBytes = session.messageBuffer
    .map((entry) => JSON.parse(entry.payload))
    .filter((payload) => payload.event?.toolCallId === cumulativeId)
    .reduce((sum, payload) => sum + countToolContentBytes(payload), 0);
  assert(cumulativeTextBytes <= MAX_TOOL_CONTENT_BYTES, "replayed tool card text stays cumulatively bounded");
} finally {
  sessions.delete(sessionId);
}

console.log(`Payload budget: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
