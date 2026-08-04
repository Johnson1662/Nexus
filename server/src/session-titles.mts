/**
 * Session Titles — narrow persistent file-backed store
 *
 * Stores session title overrides in ~/.nexus/session-titles.json
 * so renames survive a bridge process restart.
 *
 * Tolerates missing / malformed data by returning no override.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync, renameSync, unlinkSync, chmodSync } from "fs";
import { dirname } from "path";
import { join } from "path";
import { randomUUID } from "crypto";

const DEFAULT_FILE = join(
  process.env.HOME || process.env.USERPROFILE || ".",
  ".nexus",
  "session-titles.json",
);
const FILE = process.env.SESSION_TITLES_FILE || DEFAULT_FILE;

interface TitleEntry {
  title: string;
  updatedAt: number;
}

let titles: Record<string, TitleEntry> | null = null;

function ensureDir(): void {
  const d = dirname(FILE);
  if (!existsSync(d)) mkdirSync(d, { recursive: true, mode: 0o700 });
  try { chmodSync(d, 0o700); } catch {}
}

function load(): Record<string, TitleEntry> {
  if (titles) return titles;
  try {
    if (existsSync(FILE)) {
      const raw = readFileSync(FILE, "utf-8");
      const parsed = JSON.parse(raw) as Record<string, TitleEntry>;
      // Validate shape — discard entries that aren't {title,updatedAt}
      for (const [k, v] of Object.entries(parsed)) {
        if (!v || typeof v.title !== "string" || typeof v.updatedAt !== "number") {
          delete parsed[k];
        }
      }
      titles = parsed;
      return titles;
    }
  } catch {
    // corrupt or missing file — treat as empty
  }
  titles = {};
  return titles;
}

function save(): void {
  ensureDir();
  // Atomic write for a single bridge process: write to temp then rename
  const data = JSON.stringify(titles, null, 2);
  const tmp = join(dirname(FILE), `.session-titles-${randomUUID()}.tmp`);
  writeFileSync(tmp, data, { encoding: "utf-8", mode: 0o600 });
  try {
    renameSync(tmp, FILE);
  } catch (error: unknown) {
    let code = "";
    if (error && typeof error === "object" && "code" in error) {
      const value = error.code;
      if (typeof value === "string") code = value;
    }
    if (code !== "EXDEV" && code !== "EEXIST" && code !== "EPERM") throw error;
    writeFileSync(FILE, data, { encoding: "utf-8", mode: 0o600 });
    try { unlinkSync(tmp); } catch {}
  }
  try { chmodSync(FILE, 0o600); } catch {}
}

/** Persist a session title override. */
export function setTitle(sessionId: string, title: string): void {
  const map = load();
  map[sessionId] = { title, updatedAt: Date.now() };
  save();
}

/** Retrieve a persisted title, or undefined. */
export function getTitle(sessionId: string): string | undefined {
  return load()[sessionId]?.title;
}

/** Remove a persisted title override. */
export function removeTitle(sessionId: string): void {
  const map = load();
  if (map[sessionId]) {
    delete map[sessionId];
    save();
  }
}

/**
 * Apply persisted titles to a sessions array in place.
 * Each session with a matching entry gets its `.title` replaced.
 */
export function applyTitles(sessions: any[]): void {
  const map = load();
  for (const s of sessions) {
    const entry = map[s.sessionId];
    if (entry) {
      s.title = entry.title;
    }
  }
}

/** Exposed for testing — reset in-memory cache. */
export function _resetCache(): void {
  titles = null;
}
