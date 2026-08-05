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

function terminalFinalStatuses(messages, terminalId) {
  return terminalMessages(messages, terminalId).filter((message) => {
    const status = message.event.status;
    return status === "completed" || status === "failed";
  });
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

  const exactAsciiResult = await callbacks.onCreateTerminal({
    command: process.execPath,
    args: ["-e", "process.stdout.write(\"a\".repeat(256 * 1024));"],
    outputByteLimit: 1024 * 1024,
  });
  await waitForExit(callbacks, exactAsciiResult.terminalId);
  const exactAsciiOutput = await callbacks.onTerminalOutput({ terminalId: exactAsciiResult.terminalId });
  assert(exactAsciiOutput.output === "a".repeat(256 * 1024), "exact 256KB callback output is retained");
  assert(exactAsciiOutput.truncated === false, "exact 256KB callback output is not truncated");

  const overrunResult = await callbacks.onCreateTerminal({
    command: process.execPath,
    args: ["-e", "process.stdout.write(\"b\".repeat(256 * 1024) + \"c\");"],
    outputByteLimit: 1024 * 1024,
  });
  await waitForExit(callbacks, overrunResult.terminalId);
  const overrunOutput = await callbacks.onTerminalOutput({ terminalId: overrunResult.terminalId });
  assert(overrunOutput.output === "b".repeat(256 * 1024), "256KB plus one callback byte keeps the cap");
  assert(overrunOutput.truncated === true, "256KB plus one callback byte marks truncation");

  const hardCapResult = await callbacks.onCreateTerminal({
    command: process.execPath,
    args: ["-e", "process.stdout.write(\"y\".repeat(300 * 1024));"],
    outputByteLimit: 1024 * 1024,
  });
  await waitForExit(callbacks, hardCapResult.terminalId);
  const cappedOutput = await callbacks.onTerminalOutput({ terminalId: hardCapResult.terminalId });
  const cappedUpdates = terminalMessages(messages, hardCapResult.terminalId);
  const cappedText = cappedUpdates.map((message) => terminalText(message, hardCapResult.terminalId)).join("");
  assert(cappedText === cappedOutput.output, "single oversized callback delta equals retained output");
  assert(cappedText === "y".repeat(256 * 1024), "single oversized chunk retains the first 256KB");
  assert(Buffer.byteLength(cappedOutput.output, "utf8") <= 256 * 1024, "single oversized output uses UTF-8 byte cap");
  assert(cappedOutput.truncated === true, "single oversized output marks truncation");
  assert(terminalFinalStatuses(messages, hardCapResult.terminalId).length === 1, "single oversized terminal finalizes once");
  assert(
    cappedUpdates.some((message) => message.event.toolCallContent?.some((item) => item.truncated === true)),
    "terminal update exposes truncation state",
  );

  const multiResult = await callbacks.onCreateTerminal({
    command: process.execPath,
    args: [
      "-e",
      "process.stdout.write(\"o\".repeat(200 * 1024)); setTimeout(() => process.stdout.write(\"e\".repeat(100 * 1024)), 20);",
    ],
    outputByteLimit: 1024 * 1024,
  });
  await waitForExit(callbacks, multiResult.terminalId);
  const multiOutput = await callbacks.onTerminalOutput({ terminalId: multiResult.terminalId });
  const multiUpdates = terminalMessages(messages, multiResult.terminalId);
  const multiText = multiUpdates.map((message) => terminalText(message, multiResult.terminalId)).join("");
  assert(multiText === multiOutput.output, "multi-chunk callback deltas equal retained output");
  assert(multiText.startsWith("o".repeat(200 * 1024)), "multi-chunk output keeps its first chunk");
  assert(multiText.endsWith("e".repeat(56 * 1024)), "multi-chunk output keeps only the remaining budget");
  assert(Buffer.byteLength(multiText, "utf8") <= 256 * 1024, "multi-chunk output stays within UTF-8 byte cap");
  assert(multiOutput.truncated === true, "multi-chunk output marks truncation");
  assert(terminalFinalStatuses(messages, multiResult.terminalId).length === 1, "multi-chunk terminal finalizes once");

  const missingResult = await callbacks.onCreateTerminal({
    command: "__nexus_terminal_command_does_not_exist__",
    args: [],
  });
  await waitForExit(callbacks, missingResult.terminalId);
  const missingOutput = await callbacks.onTerminalOutput({ terminalId: missingResult.terminalId });
  const missingFinalStatuses = terminalFinalStatuses(messages, missingResult.terminalId);
  assert(missingFinalStatuses.length === 1, "spawn error followed by close emits one final status");
  assert(missingFinalStatuses[0]?.event.status === "failed", "spawn error followed by close is failed");
  assert(missingOutput.exitStatus?.exitCode === -1, "spawn error keeps the legacy exit code");

  const oneChunk = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 256 * 1024 };
  appendTerminalOutput(oneChunk, "x".repeat(300 * 1024));
  assert(oneChunk.output === "x".repeat(256 * 1024), "single oversized helper input keeps the first 256KB");
  assert(oneChunk.pendingDelta === oneChunk.output, "single oversized helper input keeps all accepted delta pending");
  assert(oneChunk.truncated === true, "single oversized helper input marks truncation");

  const exactUtf8Text = "é".repeat(128 * 1024);
  const exactUtf8 = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 256 * 1024 };
  appendTerminalOutput(exactUtf8, exactUtf8Text);
  assert(Buffer.byteLength(exactUtf8.output, "utf8") === 256 * 1024, "exact 256KB UTF-8 helper output fills the cap");
  assert(exactUtf8.output === exactUtf8Text, "exact 256KB UTF-8 helper output is retained");
  assert(exactUtf8.truncated === false, "exact 256KB UTF-8 helper output is not truncated");

  const exactUtf8Overrun = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 256 * 1024 };
  appendTerminalOutput(exactUtf8Overrun, exactUtf8Text + "x");
  assert(exactUtf8Overrun.output === exactUtf8Text, "256KB plus one helper byte keeps the cap");
  assert(exactUtf8Overrun.truncated === true, "256KB plus one helper byte marks truncation");

  const multiChunk = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 256 * 1024 };
  appendTerminalOutput(multiChunk, "o".repeat(200 * 1024));
  const firstDelta = multiChunk.pendingDelta;
  multiChunk.pendingDelta = "";
  appendTerminalOutput(multiChunk, "e".repeat(100 * 1024));
  const secondDelta = multiChunk.pendingDelta;
  assert(multiChunk.output === firstDelta + secondDelta, "multi-chunk helper output equals cumulative accepted deltas");
  assert(secondDelta === "e".repeat(56 * 1024), "multi-chunk helper keeps only remaining bytes");
  assert(Buffer.byteLength(multiChunk.output, "utf8") <= 256 * 1024, "multi-chunk helper uses the UTF-8 byte cap");
  assert(multiChunk.truncated === true, "multi-chunk helper marks truncation");

  const boundary = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 4 };
  appendTerminalOutput(boundary, "中🙂");
  assert(boundary.output === "中", "UTF-8 cap never splits a Chinese code point");
  assert(boundary.pendingDelta === boundary.output, "Unicode boundary delta contains complete code points");
  assert(boundary.truncated === true, "Unicode overflow marks truncation");

  const unicode = "你好🙂世界";
  const unicodeTerminal = { output: "", pendingDelta: "", truncated: false, outputByteLimit: 256 * 1024 };
  const unicodeDecoder = new StringDecoder("utf8");
  const unicodeBytes = Buffer.from(unicode);
  appendTerminalOutput(unicodeTerminal, unicodeDecoder.write(unicodeBytes.subarray(0, 2)));
  appendTerminalOutput(unicodeTerminal, unicodeDecoder.write(unicodeBytes.subarray(2, 7)));
  appendTerminalOutput(unicodeTerminal, unicodeDecoder.write(unicodeBytes.subarray(7)));
  appendTerminalOutput(unicodeTerminal, unicodeDecoder.end());
  assert(unicodeTerminal.output === unicode, "split UTF-8 chunks decode without replacement characters");
  assert([...unicodeTerminal.output].join("") === unicode, "split UTF-8 chunks preserve Unicode code points");
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
