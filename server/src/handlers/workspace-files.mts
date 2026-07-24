import { execFile } from "node:child_process";
import { readdir, stat } from "node:fs/promises";
import { join, relative, basename } from "node:path";
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

// ── Helpers ──

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
    // Get git status
    let statusMap: Map<string, string>;
    try {
      const stdout = await git(cwd, ["status", "--porcelain", "-u"], 5000);
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
        const rel = relative(cwd, fp).replace(/\\/g, "/");
        if (e.isDirectory()) {
          files.push({ path: rel + "/", name: e.name, type: "directory", status: "" });
          await walk(fp, depth + 1);
        } else if (e.isFile()) {
          const s = statusMap.get(rel) || "";
          files.push({ path: rel, name: e.name, type: "file", status: s });
        }
      }
    }
    await walk(cwd, 0);

    ws.send(JSON.stringify({ type: "workspace_files", cwd, files }));
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
    // Try HEAD diff first (covers staged + unstaged), fall back to unstaged-only
    let diff = "";
    let triedStaged = false;
    try {
      diff = await git(cwd, ["diff", "HEAD", "--", filePath], 10000);
    } catch {
      // HEAD diff may fail if file is new (no HEAD commit for it)
      try {
        diff = await git(cwd, ["diff", "--staged", "--", filePath], 10000);
        triedStaged = true;
      } catch {}
    }
    if (!diff && !triedStaged) {
      try {
        diff = await git(cwd, ["diff", "--staged", "--", filePath], 10000);
      } catch {}
    }
    // If still no diff and file is untracked, read content as new file
    if (!diff) {
      try {
        const { readFile } = await import("node:fs/promises");
        const { join: j } = await import("node:path");
        const content = await readFile(j(cwd, filePath), "utf-8");
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
    const stdout = await git(
      cwd,
      ["log", "--oneline", "--date=short", "--format=%h|%ad|%an|%s", "-n", "20", "--", filePath],
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
    const fullPath = join(cwd, filePath);
    // Safety: prevent directory traversal
    if (!fullPath.startsWith(cwd)) {
      ws.send(JSON.stringify({ type: "file_content", path: filePath, content: "", error: "path traversal denied" }));
      return;
    }
    const content = await fs.readFile(fullPath, "utf-8");
    ws.send(JSON.stringify({ type: "file_content", path: filePath, content }));
  } catch (err: any) {
    ws.send(JSON.stringify({ type: "file_content", path: filePath, content: "", error: err.message }));
  }
}
