import { mkdtempSync, rmSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import assert from "node:assert/strict";
import { HerdrCliClient, HerdrCliError, resolveHerdrBinary } from "../dist/discovery/herdr-cli.mjs";

console.log("=== Testing Herdr CLI transport ===");

const FAKE = `#!/usr/bin/env node
const argv = process.argv.slice(2);
if (argv.includes("__text__")) { process.stdout.write("plain snapshot text\\n"); process.exit(0); }
if (argv.includes("__sleep__")) { setTimeout(() => process.exit(0), 5000); }
if (argv.includes("__exit1__")) { process.stderr.write("herdr exploded\\n"); process.exit(1); }
process.stdout.write(JSON.stringify({ id: "cli:fake", result: { type: "ok" } }) + "\\n");
`;

const dir = mkdtempSync(join(tmpdir(), "nexus-herdr-cli-test-"));
const fakeBin = join(dir, "herdr");
writeFileSync(fakeBin, FAKE, "utf8");
chmodSync(fakeBin, 0o755);
process.env.HERDR_BIN_PATH = fakeBin;

try {
  assert.equal(resolveHerdrBinary(), fakeBin, "resolveHerdrBinary honours HERDR_BIN_PATH");

  // Envelope unwrapping.
  const result = await HerdrCliClient.runJson(["anything"]);
  assert.equal(result.type, "ok", "runJson unwraps the CLI envelope");

  // A command that prints human text must fail loudly rather than silently.
  const badJson = await HerdrCliClient.runJson(["__text__"]).then(() => null, (e) => e);
  assert(badJson instanceof HerdrCliError, "non-JSON output rejects");
  assert.equal(badJson.code, "HERDR_BAD_JSON", "non-JSON output rejects with HERDR_BAD_JSON");
  assert(badJson.message.includes("plain snapshot text"), "HERDR_BAD_JSON message includes the offending output");

  // Raw text mode still works for the same command.
  const text = await HerdrCliClient.run(["__text__"]);
  assert.equal(text.trim(), "plain snapshot text", "run() returns raw stdout");

  // Non-zero exit surfaces stderr.
  const exitErr = await HerdrCliClient.run(["__exit1__"]).then(() => null, (e) => e);
  assert(exitErr instanceof HerdrCliError && exitErr.code === "HERDR_EXIT", "non-zero exit rejects with HERDR_EXIT");
  assert(exitErr.message.includes("herdr exploded"), "HERDR_EXIT message carries stderr");

  // Timeout kills the child.
  const timeoutErr = await HerdrCliClient.run(["__sleep__"], { timeoutMs: 300 }).then(() => null, (e) => e);
  assert(timeoutErr instanceof HerdrCliError && timeoutErr.code === "HERDR_TIMEOUT", "hanging command rejects with HERDR_TIMEOUT");

  // Missing binary is authoritative, never a silent PATH fallback.
  process.env.HERDR_BIN_PATH = join(dir, "missing-herdr");
  assert.equal(resolveHerdrBinary(), null, "unresolvable HERDR_BIN_PATH resolves to null");
  const missingErr = await HerdrCliClient.run(["anything"]).then(() => null, (e) => e);
  assert(missingErr instanceof HerdrCliError && missingErr.code === "HERDR_BIN_NOT_FOUND", "missing binary rejects with HERDR_BIN_NOT_FOUND");
} finally {
  delete process.env.HERDR_BIN_PATH;
  rmSync(dir, { recursive: true, force: true });
}

console.log("ALL HERDR CLI TESTS PASSED!");
