import { EventEmitter } from "node:events";
import process from "node:process";
import { StringDecoder } from "node:string_decoder";
import { appendTerminalOutput, createAcpCallbacks } from "./dist/acp-callbacks.mjs";
import { sessionManager } from "./dist/session-manager.mjs";

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

function fakeTransport(messages) {
  const transport = new EventEmitter();
  transport.send = (message) => messages.push(JSON.parse(String(message)));
  return transport;
}

function fakeSession(transport) {
  return {
    ws: transport,
    ownerTransport: transport,
    terminals: new Map(),
    toolCallIdMap: new Map(),
    lastToolCallId: "tool-call",
    messageBuffer: [],
    replayBytes: 0,
  };
}

function terminalMessages(messages, terminalId) {
  return messages.filter((message) => {
    const event = message?.event;
    return event?.sessionUpdate === "tool_call_update"
      && event.toolCallContent?.some((content) => content?.terminalId === terminalId);
  });
}

function terminalText(message, terminalId) {
  const content = message.event.toolCallContent.find((item) => item?.terminalId === terminalId);
  return content?.content?.text ?? "";
}

async function waitForExit(callbacks, terminalId) {
  let timeout;
  try {
    await Promise.race([
      callbacks.onWaitForTerminalExit({ terminalId }),
      new Promise((_, reject) => {
        timeout = setTimeout(() => reject(new Error("terminal exit timed out")), 10_000);
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
  // Allow the child stream to deliver data after the exit event on all platforms.
  await new Promise((resolve) => setTimeout(resolve, 100));
}

const sessions = sessionManager.getAllSessions();
const terminalSessionId = "terminal-delta-test";
const messages = [];
const transport = fakeTransport(messages);
const session = fakeSession(transport);
sessions.set(terminalSessionId, session);

try {
  const callbacks = createAcpCallbacks({
    getSessionId: () => terminalSessionId,
    cwd: process.cwd(),
    toolCallIdMap: session.toolCallIdMap,
  });

  const deltaScript = `
    const chunk = "x".repeat(1024);
    let count = 0;
    const timer = setInterval(() => {
      process.stdout.write(chunk);
      count += 1;
      if (count === 100) {
        clearInterval(timer);
        setTimeout(() => process.exit(0), 100);
      }
    }, 4);
  `;
  const deltaResult = await callbacks.onCreateTerminal({
    command: process.execPath,
    args: ["-e", deltaScript],
    outputByteLimit: 200 * 1024,
  });
  await waitForExit(callbacks, deltaResult.terminalId);

  const updates = terminalMessages(messages, deltaResult.terminalId);
  const receivedText = updates.map((message) => terminalText(message, deltaResult.terminalId)).join("");
  const sentBytes = updates.reduce((total, message) => total + Buffer.byteLength(JSON.stringify(message)), 0);
  assert(receivedText.length === 100 * 1024, "terminal deltas reconstruct all 100KB of output");
  assert(updates.length < 50, `terminal output is aggregated (${updates.length} messages)`);
  assert(sentBytes < 512 * 1024, `terminal wire size stays near output size (${sentBytes} bytes)`);
  assert(
    updates.some((message) => message.event.status === "completed" || message.event.status === "failed"),
    "terminal final status event arrives",
  );

  const hardCapResult = await callbacks.onCreateTerminal({
    command: process.execPath,
    args: ["-e", "process.stdout.write(\"y\".repeat(300 * 1024));"],
    outputByteLimit: 1024 * 1024,
  });
  await waitForExit(callbacks, hardCapResult.terminalId);
  const cappedOutput = await callbacks.onTerminalOutput({ terminalId: hardCapResult.terminalId });
  const cappedUpdates = terminalMessages(messages, hardCapResult.terminalId);
  const cappedText = cappedUpdates.map((message) => terminalText(message, hardCapResult.terminalId)).join("");
  assert(cappedOutput.output.length <= 256 * 1024, "terminal output obeys the 256KB hard cap");
  assert(Buffer.byteLength(cappedOutput.output, "utf8") <= 256 * 1024, "terminal retained output uses UTF-8 byte cap");
  assert(cappedOutput.truncated === true, "terminal output marks truncation");
  assert(Buffer.byteLength(cappedText, "utf8") > 0, "truncated terminal sends retained delta to the client");
  assert(
    cappedUpdates.some((message) => message.event.status === "completed" || message.event.status === "failed"),
    "truncated terminal still sends a final status event",
  );
  assert(
    cappedUpdates.some((message) => message.event.toolCallContent?.some((item) => item.truncated === true)),
    "terminal update exposes truncation state",
  );

  const oneChunk = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 256 * 1024 };
  appendTerminalOutput(oneChunk, "x".repeat(300 * 1024));
  assert(Buffer.byteLength(oneChunk.output, "utf8") <= 256 * 1024, "single oversized chunk retains the byte-limited suffix");
  assert(Buffer.byteLength(oneChunk.pendingDelta, "utf8") === Buffer.byteLength(oneChunk.output, "utf8"), "single oversized chunk keeps retained delta pending");
  assert(oneChunk.truncated === true, "single oversized chunk marks truncation");

  const multiChunk = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 256 * 1024 };
  appendTerminalOutput(multiChunk, "o".repeat(200 * 1024));
  multiChunk.pendingDelta = "";
  appendTerminalOutput(multiChunk, "e".repeat(100 * 1024));
  assert(Buffer.byteLength(multiChunk.output, "utf8") <= 256 * 1024, "mixed output shares the byte limit");
  assert(multiChunk.pendingDelta === "e".repeat(100 * 1024), "already flushed output does not erase the new pending tail");
  assert(multiChunk.truncated === true, "mixed output marks truncation");

  const unicode = "你好🙂世界";
  const unicodeTerminal = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 256 * 1024 };
  const unicodeDecoder = new StringDecoder("utf8");
  const unicodeBytes = Buffer.from(unicode);
  appendTerminalOutput(unicodeTerminal, unicodeDecoder.write(unicodeBytes.subarray(0, 2)));
  appendTerminalOutput(unicodeTerminal, unicodeDecoder.write(unicodeBytes.subarray(2)));
  appendTerminalOutput(unicodeTerminal, unicodeDecoder.end());
  assert(unicodeTerminal.output === unicode, "split UTF-8 chunks decode without replacement characters");
} catch (error) {
  failed += 1;
  console.error(`FAIL: terminal callback integration: ${error instanceof Error ? error.message : String(error)}`);
} finally {
  sessions.delete(terminalSessionId);
}

const replaySessionId = "terminal-replay-test";
const replaySession = fakeSession(fakeTransport([]));
sessions.set(replaySessionId, replaySession);
try {
  for (let index = 0; index < 30; index += 1) {
    sessionManager.bufferAgentEvent(replaySessionId, {
      type: "agent_event",
      payload: "字".repeat(100 * 1024),
    });
  }
  const retainedBytes = replaySession.messageBuffer.reduce((total, message) => total + Buffer.byteLength(message.payload, "utf8"), 0);
  assert(retainedBytes <= 2 * 1024 * 1024, "replay buffer stays within the 2MB UTF-8 byte limit");
  assert(replaySession.replayBytes === retainedBytes, "replay byte accounting matches retained UTF-8 payloads");
  assert(
    replaySession.messageBuffer.every((message) => message.payloadBytes === Buffer.byteLength(message.payload, "utf8")),
    "replay entries store UTF-8 payload byte lengths",
  );
  assert(replaySession.messageBuffer.length < 30, "UTF-8 byte limit trims oversized replay history");
  assert(replaySession.messageBuffer.length >= 1, "replay buffer retains at least one message");
} catch (error) {
  failed += 1;
  console.error(`FAIL: replay byte limit: ${error instanceof Error ? error.message : String(error)}`);
} finally {
  sessions.delete(replaySessionId);
}

console.log(`Terminal delta: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
