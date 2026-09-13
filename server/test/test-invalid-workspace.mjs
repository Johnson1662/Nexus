import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { resolveExplicitCwd, WorkspaceError } from "../dist/path-utils.mjs";

console.log("=== Testing fail-closed workspace resolution ===");

const dir = mkdtempSync(join(tmpdir(), "nexus-cwd-"));
const defaultDir = join(dir, "default");

try {
  // 1. No cwd supplied is legitimate: fall back to the default directory.
  const fallback = resolveExplicitCwd(undefined, defaultDir);
  assert.equal(fallback, defaultDir, "a missing cwd uses the default directory");
  const blank = resolveExplicitCwd("   ", defaultDir);
  assert.equal(blank, defaultDir, "a blank cwd is treated as missing");

  // 2. A real directory resolves to its canonical path.
  const real = resolveExplicitCwd(dir, defaultDir);
  assert(real.endsWith(dir.split("/").pop()), `a real directory resolves: ${real}`);

  // 3. An explicit cwd that does not exist must fail closed, never silently
  //    relocate the agent to another directory.
  const missing = join(dir, "does-not-exist");
  let thrown = null;
  try {
    resolveExplicitCwd(missing, defaultDir);
  } catch (err) {
    thrown = err;
  }
  assert(thrown instanceof WorkspaceError, "a missing explicit cwd throws WorkspaceError");
  assert.equal(thrown.code, "INVALID_WORKSPACE", "the error carries INVALID_WORKSPACE");
  assert(thrown.message.includes(missing), "the error names the rejected path");

  // 4. A file is not a workspace directory either.
  const { writeFileSync } = await import("node:fs");
  const file = join(dir, "file.txt");
  writeFileSync(file, "x", "utf8");
  let fileThrown = null;
  try {
    resolveExplicitCwd(file, defaultDir);
  } catch (err) {
    fileThrown = err;
  }
  assert(fileThrown instanceof WorkspaceError, "a file path throws WorkspaceError");
  assert.equal(fileThrown.code, "INVALID_WORKSPACE", "a file path reports INVALID_WORKSPACE");
} finally {
  rmSync(dir, { recursive: true, force: true });
}

console.log("ALL INVALID WORKSPACE TESTS PASSED!");
