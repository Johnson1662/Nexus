import { execFile } from "node:child_process";
import { readdir, realpath, stat } from "node:fs/promises";
import { lstatSync } from "node:fs";
import { join, relative, basename, dirname, resolve, isAbsolute } from "node:path";
import type { WebSocket } from "ws";

export interface WorkspaceFile {
  path: string;
  name: string;
  type: "file" | "directory";
  status: string; // git status: M, A, D, ??, "" (untracked/unmodified)
}

export interface GitLogEntry {
  hash: string;
  date: string;
  message: string;
  author: string;
}

const MAX_FILE_BYTES = 4 * 1024 * 1024;

// ── Helpers ──

function isWithin(root: string, target: string): boolean {
  const rel = relative(root, target);
  return rel === "" || (!rel.startsWith("..") && !isAbsolute(rel));
}

async function resolveWorkspaceRoot(cwd: string): Promise<string> {
  const root = await realpath(cwd);
  await readdir(root, { withFileTypes: true });
  return root;
}

async function resolveWorkspaceEntry(root: string, filePath: string, allowMissing = false): Promise<string> {
  const lexical = resolve(root, filePath);
  if (!isWithin(root, lexical)) throw new Error("path traversal denied");
  let canonical: string;
  try {
    canonical = await realpath(lexical);
  } catch (error) {
    if (!allowMissing) throw error;
    try {
      if (lstatSync(lexical).isSymbolicLink()) throw new Error("path traversal denied");
    } catch (linkError: unknown) {
      if (!(linkError instanceof Error && "code" in linkError && linkError.code === "ENOENT")) throw linkError;
    }
    const parent = await realpath(dirname(lexical));
    if (!isWithin(root, parent)) throw new Error("path traversal denied");
    return join(parent, basename(lexical));
  }
  if (!isWithin(root, canonical)) throw new Error("path traversal denied");
  return canonical;
}

function git(cwd: string, args: string[], timeoutMs = 8000): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile("git", args, { cwd, timeout: timeoutMs, maxBuffer: 512 * 1024 }, (err, stdout) => {
      if (err) { reject(err); return; }
      resolve(stdout);
    });
  });
}

function parseGitStatus(porcelain: string): Map<string, string> {
  const map = new Map<string, string>();
  for (const line of porcelain.split("\n")) {
    if (line.length < 3) continue;
    const code = line.slice(0, 2).trim();
    const filePath = line.slice(3).trim();
    if (filePath) map.set(filePath, code);
  }
  return map;
}

// ── Handlers ──

export async function handleListWorkspaceFiles(
  ws: WebSocket,
  params: { cwd: string },
): Promise<void> {
  const { cwd } = params;
  if (!cwd) {
    ws.send(JSON.stringify({ type: "workspace_files", cwd: "", files: [] }));
    return;
  }

  try {
    const root = await resolveWorkspaceRoot(cwd);
    // Get git status
    let statusMap: Map<string, string>;
    try {
      const stdout = await git(root, ["status", "--porcelain", "-u"], 5000);
      statusMap = parseGitStatus(stdout);
    } catch {
      statusMap = new Map();
    }

    // List workspace files (non-.git, max depth 3 to avoid explosion)
    const files: WorkspaceFile[] = [];
    async function walk(dir: string, depth: number): Promise<void> {
      if (depth > 3) return;
      let entries;
      try {
        entries = await readdir(dir, { withFileTypes: true });
      } catch {
        return;
      }
      for (const e of entries) {
        if (e.name.startsWith(".")) continue;
        if (e.name === "node_modules") continue;
        const fp = join(dir, e.name);
        const rel = relative(root, fp).replace(/\\/g, "/");
        if (e.isDirectory()) {
          files.push({ path: rel + "/", name: e.name, type: "directory", status: "" });
          await walk(fp, depth + 1);
        } else if (e.isFile()) {
          const s = statusMap.get(rel) || "";
          files.push({ path: rel, name: e.name, type: "file", status: s });
        }
      }
    }
    await walk(root, 0);

    ws.send(JSON.stringify({ type: "workspace_files", cwd: root, files }));
  } catch (err: any) {
    ws.send(JSON.stringify({ type: "workspace_files", cwd, files: [], error: err.message }));
  }
}

export async function handleFileDiff(
  ws: WebSocket,
  params: { cwd: string; path: string },
): Promise<void> {
  const { cwd, path: filePath } = params;
  if (!cwd || !filePath) {
    ws.send(JSON.stringify({ type: "file_diff", path: filePath || "", diff: "", error: "missing cwd or path" }));
    return;
  }

  try {
    const root = await resolveWorkspaceRoot(cwd);
    const canonicalPath = await resolveWorkspaceEntry(root, filePath, true);
    const relativePath = relative(root, canonicalPath).replace(/\\/g, "/");
    // Try HEAD diff first (covers staged + unstaged), fall back to unstaged-only
    let diff = "";
    let triedStaged = false;
    try {
      diff = await git(root, ["diff", "HEAD", "--", relativePath], 10000);
    } catch {
      // HEAD diff may fail if file is new (no HEAD commit for it)
      try {
        diff = await git(root, ["diff", "--staged", "--", relativePath], 10000);
        triedStaged = true;
      } catch {}
    }
    if (!diff && !triedStaged) {
      try {
        diff = await git(root, ["diff", "--staged", "--", relativePath], 10000);
      } catch {}
    }
    // If still no diff and file is untracked, read content as new file
    if (!diff) {
      try {
        const { readFile } = await import("node:fs/promises");
        const fileStat = await stat(canonicalPath);
        if (!fileStat.isFile() || fileStat.size > MAX_FILE_BYTES) {
          throw new Error(`file exceeds ${MAX_FILE_BYTES} byte limit`);
        }
        const content = await readFile(canonicalPath, "utf-8");
        diff = content;
        ws.send(JSON.stringify({ type: "file_diff", path: filePath, diff }));
        return;
      } catch {}
    }
    ws.send(JSON.stringify({ type: "file_diff", path: filePath, diff }));
  } catch (err: any) {
    ws.send(JSON.stringify({ type: "file_diff", path: filePath, diff: "", error: err.message }));
  }
}

export async function handleFileLog(
  ws: WebSocket,
  params: { cwd: string; path: string },
): Promise<void> {
  const { cwd, path: filePath } = params;
  if (!cwd || !filePath) {
    ws.send(JSON.stringify({ type: "file_log", path: filePath || "", entries: [] }));
    return;
  }

  try {
    const root = await resolveWorkspaceRoot(cwd);
    const canonicalPath = await resolveWorkspaceEntry(root, filePath, true);
    const relativePath = relative(root, canonicalPath).replace(/\\/g, "/");
    const stdout = await git(
      root,
      ["log", "--oneline", "--date=short", "--format=%h|%ad|%an|%s", "-n", "20", "--", relativePath],
      8000,
    );
    const entries: GitLogEntry[] = stdout
      .split("\n")
      .filter((l) => l.includes("|"))
      .map((l) => {
        const [hash, date, author, ...msgParts] = l.split("|");
        return { hash, date, author, message: msgParts.join("|") };
      });
    ws.send(JSON.stringify({ type: "file_log", path: filePath, entries }));
  } catch (err: any) {
    ws.send(JSON.stringify({ type: "file_log", path: filePath, entries: [], error: err.message }));
  }
}

export async function handleFileRead(
  ws: WebSocket,
  params: { cwd: string; path: string },
): Promise<void> {
  const { cwd, path: filePath } = params;
  if (!cwd || !filePath) {
    ws.send(JSON.stringify({ type: "file_content", path: filePath || "", content: "", error: "missing cwd or path" }));
    return;
  }

  try {
    const fs = await import("node:fs/promises");
    const root = await resolveWorkspaceRoot(cwd);
    const fullPath = await resolveWorkspaceEntry(root, filePath);
    const stat = await fs.stat(fullPath);
    if (!stat.isFile() || stat.size > MAX_FILE_BYTES) {
      throw new Error(`file exceeds ${MAX_FILE_BYTES} byte limit`);
    }
    const content = await fs.readFile(fullPath, "utf-8");
    ws.send(JSON.stringify({ type: "file_content", path: filePath, content }));
  } catch (err: any) {
    ws.send(JSON.stringify({ type: "file_content", path: filePath, content: "", error: err.message }));
  }
}
