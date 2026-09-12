import { EventEmitter } from "node:events";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { parseClientMessage } from "../dist/protocol-validation.mjs";

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (condition) passed += 1;
  else {
    failed += 1;
    console.error(`FAIL: ${message}`);
  }
}

const invalidInputs = [
  "null",
  "[]",
  "{}",
  JSON.stringify({ type: 123 }),
  JSON.stringify({ type: "input", text: {} }),
  JSON.stringify({ type: "cancel", sessionId: 123 }),
  JSON.stringify({ type: "session", message: null }),
];

for (const raw of invalidInputs) {
  assert(parseClientMessage(raw).ok === false, `rejects malformed message ${raw}`);
}

const valid = parseClientMessage(JSON.stringify({ type: "heartbeat", ts: Date.now() }));
assert(valid.ok === true, "accepts a valid transport message");

function nestedSession(depth) {
  let raw = JSON.stringify({ type: "heartbeat" });
  for (let index = 0; index < depth; index += 1) {
    raw = `{"type":"session","message":${raw}}`;
  }
  return raw;
}

for (const depth of [100, 1000, 10000]) {
  let parsed;
  try {
    parsed = parseClientMessage(nestedSession(depth));
  } catch (error) {
    parsed = { ok: true };
    console.error(`FAIL: nested session depth ${depth} escaped validation: ${String(error)}`);
  }
  assert(parsed.ok === false, `rejects nested session depth ${depth} without recursion`);
}

const originalHome = process.env.HOME;
const originalUserProfile = process.env.USERPROFILE;
const testHome = mkdtempSync(join(tmpdir(), "nexus-protocol-test-"));
process.env.HOME = testHome;
process.env.USERPROFILE = testHome;
const { handleIncomingConnection } = await import("../dist/server.mjs");

const transport = new EventEmitter();
transport.sent = [];
transport.send = (message) => transport.sent.push(JSON.parse(String(message)));
handleIncomingConnection(transport, "protocol-test-host");

for (const raw of invalidInputs) {
  transport.emit("message", Buffer.from(raw));
}
assert(
  transport.sent.filter((message) => message.type === "error" && message.code === "INVALID_MESSAGE").length === invalidInputs.length,
  "invalid WS messages receive protocol errors without reaching handlers",
);

transport.emit("message", Buffer.from(JSON.stringify({ type: "heartbeat", ts: 42 })));
assert(transport.sent.some((message) => message.type === "heartbeat" && message.ts === 42), "heartbeat still reaches the transport handler");

transport.emit("message", Buffer.from(nestedSession(10000)));
assert(
  transport.sent.some((message) => message.type === "error" && message.code === "INVALID_MESSAGE"),
  "deeply nested session receives INVALID_MESSAGE instead of escaping the WS handler",
);
transport.emit("message", Buffer.from(JSON.stringify({ type: "heartbeat", ts: 43 })));
assert(transport.sent.some((message) => message.type === "heartbeat" && message.ts === 43), "bridge stays alive after deeply nested input");

transport.emit("close");
if (originalHome === undefined) delete process.env.HOME;
else process.env.HOME = originalHome;
if (originalUserProfile === undefined) delete process.env.USERPROFILE;
else process.env.USERPROFILE = originalUserProfile;
console.log(`Protocol validation: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
