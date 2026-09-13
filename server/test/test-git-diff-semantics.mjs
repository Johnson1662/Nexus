import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

console.log("=== Testing Git diff semantics ===");

const { handleFileDiff } = await import("../dist/handlers/workspace-files.mjs");

const repo = mkdtempSync(join(tmpdir(), "nexus-git-diff-"));
const git = (args) => execFileSync("git", args, { cwd: repo, encoding: "utf8" });

try {
  git(["init", "-q"]);
  git(["config", "user.email", "test@example.com"]);
  git(["config", "user.name", "Test"]);
  writeFileSync(join(repo, "tracked.txt"), "original\n", "utf8");
  git(["add", "tracked.txt"]);
  git(["commit", "-q", "-m", "initial"]);

  const diff = async (path) => {
    let out = null;
    const ws = { send: (raw) => { out = JSON.parse(raw); } };
    await handleFileDiff(ws, { cwd: repo, path });
    return out;
  };

  // 1. A tracked file that matches HEAD has no changes: an empty diff, NOT the
  //    whole file rendered as a new-file diff.
  const clean = await diff("tracked.txt");
  assert.equal(clean.type, "file_diff", "clean tracked file replies with file_diff");
  assert.equal(clean.diff, "", "a tracked file with no changes has an empty diff");
  assert(!/original/.test(clean.diff ?? ""), "the file body is not reported as a diff");

  // 2. A modified tracked file reports the change.
  writeFileSync(join(repo, "tracked.txt"), "original\nchanged\n", "utf8");
  const modified = await diff("tracked.txt");
  assert(modified.diff.includes("+changed"), `a modification is reported: ${modified.diff}`);

  // 3. An untracked file keeps the synthetic new-file diff.
  writeFileSync(join(repo, "fresh.txt"), "brand new\n", "utf8");
  const untracked = await diff("fresh.txt");
  assert(untracked.diff.includes("brand new"), "an untracked file shows its content");
} finally {
  rmSync(repo, { recursive: true, force: true });
}

console.log("ALL GIT DIFF SEMANTICS TESTS PASSED!");
