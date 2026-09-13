import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  sanitizeLogText,
  rotateLogFile,
} from "../dist/daemon/log-governance.mjs";

console.log("=== Testing Log Governance ===");

// 1. Log sanitization
const input = "User Authorization: Bearer sk-ant-api03-abcdef1234567890 and token=supersecrettoken123 password='mysecretpassword123'";
const sanitized = sanitizeLogText(input, ["supersecrettoken123"]);

assert(!sanitized.includes("sk-ant-api03-abcdef1234567890"), "API key should be redacted");
assert(!sanitized.includes("supersecrettoken123"), "Explicit secret should be redacted");
assert(!sanitized.includes("mysecretpassword123"), "Password should be redacted");
assert(sanitized.includes("Bearer [REDACTED]"), "Bearer token redacted");
assert(sanitized.includes("token=[REDACTED]"), "Query token redacted");
console.log("  ✓ sanitizeLogText redacts bearer tokens, query tokens, and passwords");

// 2. Log file rotation
const testDir = mkdtempSync(join(tmpdir(), "nexus-log-gov-"));
const logPath = join(testDir, "test-daemon.log");

// Small file does not rotate
writeFileSync(logPath, "short log line\n");
const rotatedSmall = rotateLogFile(logPath, 1000);
assert.equal(rotatedSmall, false, "small log should not rotate");

// Oversized file rotates
writeFileSync(logPath, "x".repeat(2000));
const rotatedLarge = rotateLogFile(logPath, 1000);
assert.equal(rotatedLarge, true, "large log should rotate");
assert.equal(statSync(`${logPath}.1`).size, 2000, "backup file created with original content");

rmSync(testDir, { recursive: true, force: true });
console.log("  ✓ rotateLogFile rotates when size exceeds threshold");

console.log("ALL LOG GOVERNANCE TESTS PASSED!\n");
