import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const { handleFileRead, handleListWorkspaceFiles } = await import("../dist/handlers/workspace-files.mjs");
const root = await mkdtemp(join(tmpdir(), "nexus-workspace-"));
const outside = `${root}-outside.txt`;
await writeFile(join(root, "inside.txt"), "safe", "utf8");
await writeFile(outside, "secret", "utf8");

const sent = [];
const ws = { send: (raw) => sent.push(JSON.parse(raw)) };
try {
  await handleFileRead(ws, { cwd: root, path: "inside.txt" });
  assert.equal(sent.pop().content, "safe");

  await handleFileRead(ws, { cwd: root, path: "../" + outside.split(/[\\/]/).pop() });
  const rejected = sent.pop();
  assert.equal(rejected.content, "");
  assert.equal(rejected.error, "path traversal denied");

  const largeRoot = await mkdtemp(join(tmpdir(), "nexus-workspace-large-"));
  try {
    await Promise.all(Array.from({ length: 5_001 }, (_value, index) =>
      writeFile(join(largeRoot, `file-${index}.txt`), "x", "utf8"),
    ));
    await handleListWorkspaceFiles(ws, { cwd: largeRoot });
    const listing = sent.pop();
    assert.equal(listing.files.length, 5_000);
    assert.equal(listing.truncated, true);
  } finally {
    await rm(largeRoot, { recursive: true, force: true });
  }

  console.log("Workspace path boundary: 4 passed, 0 failed");
} finally {
  await rm(root, { recursive: true, force: true });
  await rm(outside, { force: true });
}
