import { existsSync, unlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomUUID } from "node:crypto";

const testFile = join(tmpdir(), `nexus-session-titles-${randomUUID()}.json`);
process.env.SESSION_TITLES_FILE = testFile;

let passed = 0;
let failed = 0;
function assert(condition, message) {
  if (condition) passed += 1;
  else { failed += 1; console.error(`FAIL: ${message}`); }
}

function removeFile() {
  try { if (existsSync(testFile)) unlinkSync(testFile); } catch { }
}

async function main() {
  const titles = await import(`./dist/session-titles.mjs?test=${randomUUID()}`);
  removeFile();
  titles._resetCache();

  titles.setTitle("s1", "Hello World");
  assert(titles.getTitle("s1") === "Hello World", "setTitle persists a title");

  titles._resetCache();
  assert(titles.getTitle("s1") === "Hello World", "title survives a store reload");

  titles.setTitle("s2", "Updated");
  const sessions = [{ sessionId: "s1", title: "old" }, { sessionId: "s2", title: "untouched" }];
  titles.applyTitles(sessions);
  assert(sessions[0].title === "Hello World" && sessions[1].title === "Updated", "list response receives persisted titles");

  removeFile();
  titles._resetCache();
  assert(titles.getTitle("missing") === undefined, "missing store is harmless");

  writeFileSync(testFile, "{bad", "utf8");
  titles._resetCache();
  assert(titles.getTitle("broken") === undefined, "malformed store is harmless");

  removeFile();
  console.log(`Session titles: ${passed} passed, ${failed} failed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((error) => { removeFile(); console.error(error); process.exit(1); });
