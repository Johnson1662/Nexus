import assert from "node:assert/strict";
import { canonicalizeWorkspacePath, areWorkspacePathsEqual } from "../dist/path-utils.mjs";

console.log("=== Testing Cross-Platform Path Canonicalization ===");

// Windows: drive letter normalized, backslashes → forward slashes, case-insensitive
assert.equal(
  canonicalizeWorkspacePath("C:\\Project\\src", "win32"),
  "C:/Project/src",
  "windows backslashes normalized and drive uppercased",
);
assert.equal(
  canonicalizeWorkspacePath("c:/project", "win32"),
  "C:/project",
  "windows drive letter upper-cased",
);
assert(areWorkspacePathsEqual("C:/Project", "c:/project", "win32"), "windows comparison is case-insensitive");
assert(areWorkspacePathsEqual("C:\\Project\\", "c:/project", "win32"), "windows trailing separator ignored");

// Linux: case-sensitive, trailing separator trimmed
assert.equal(canonicalizeWorkspacePath("/tmp/Project/", "linux"), "/tmp/Project", "linux trailing slash trimmed");
assert(areWorkspacePathsEqual("/tmp/Project", "/tmp/Project", "linux"), "identical linux paths match");
assert(!areWorkspacePathsEqual("/tmp/Project", "/tmp/project", "linux"), "linux comparison is case-sensitive");

// macOS: conservative case-sensitive
assert(!areWorkspacePathsEqual("/Users/me/Project", "/users/me/project", "darwin"), "darwin stays case-sensitive");

// Empty input is defensive but not equal to anything meaningful
assert.equal(canonicalizeWorkspacePath("   ", "linux"), "", "blank input → empty canonical path");

console.log("ALL PATH CANONICALIZATION TESTS PASSED!");

// The session aggregator compares a requested cwd against each agent's reported
// cwd; that comparison must follow platform case rules instead of folding case.
{
  const { areWorkspacePathsEqual: eq, canonicalizeWorkspacePath: canon } = await import("../dist/path-utils.mjs");
  const requested = canon("/media/data/Project");
  const reported = canon("/media/data/project");
  assert(!eq(requested, reported, "linux"), "case-different cwds must not merge on linux");
  assert(eq(requested, reported, "win32"), "case-different cwds must merge on win32");
  assert(!eq(requested, reported, "darwin"), "case-different cwds must not merge on darwin");
}
