import net from "node:net";
import path from "node:path";
import { homedir } from "node:os";
import { existsSync, readdirSync, readlinkSync, statSync, realpathSync, readFileSync } from "node:fs";
import { execSync } from "node:child_process";

// ── Types ─────────────────────────────────────────────────────────────

export interface HerdrAgentInfo {
  pane_id: string;
  agent: string;
  agent_status: "working" | "idle" | "blocked" | "done" | "unknown";
  cwd: string;
  foreground_cwd?: string;
  terminal_title?: string;
  terminal_title_stripped?: string;
  workspace_id?: string;
  tab_id?: string;
  agent_session?: {
    source?: string;
    agent?: string;
    kind?: string;
    value?: string;
  };
}

interface HerdrRpcResponse<T = unknown> {
  id?: string;
  result?: T;
  error?: {
    code: string;
    message: string;
  };
}

// ── Low-level Socket Client ───────────────────────────────────────────

let requestCounter = 0;

export function getHerdrSocketPath(): string {
  return process.env.HERDR_SOCKET_PATH ?? path.join(homedir(), ".config", "herdr", "herdr.sock");
}

export function isHerdrAvailable(): boolean {
  try {
    return existsSync(getHerdrSocketPath());
  } catch {
    return false;
  }
}

export async function sendHerdrRequest<T = unknown>(
  method: string,
  params: Record<string, unknown> = {},
  timeoutMs = 2000,
): Promise<T> {
  const socketPath = getHerdrSocketPath();
  if (!existsSync(socketPath)) {
    throw new Error(`Herdr socket not found at ${socketPath}`);
  }

  const id = `nexus_req_${++requestCounter}_${Date.now()}`;
  const payload = JSON.stringify({ id, method, params }) + "\n";

  return new Promise<T>((resolve, reject) => {
    let settled = false;
    const client = net.createConnection(socketPath);
    let buffer = "";

    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        client.destroy();
        reject(new Error(`Herdr RPC timeout (${timeoutMs}ms) for ${method}`));
      }
    }, timeoutMs);

    client.on("connect", () => {
      client.write(payload);
    });

    client.on("data", (chunk) => {
      buffer += chunk.toString("utf-8");
      if (buffer.includes("\n")) {
        const line = buffer.slice(0, buffer.indexOf("\n")).trim();
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          client.end();
          try {
            const resp = JSON.parse(line) as HerdrRpcResponse<T>;
            if (resp.error) {
              reject(new Error(`Herdr RPC error [${resp.error.code}]: ${resp.error.message}`));
            } else {
              resolve(resp.result as T);
            }
          } catch (err) {
            reject(new Error(`Failed to parse Herdr response: ${String(err)}`));
          }
        }
      }
    });

    client.on("error", (err) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(err);
      }
    });

    client.on("close", () => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(new Error("Connection closed before response received"));
      }
    });
  });
}

// ── Herdr Adapter API ─────────────────────────────────────────────────

export class HerdrAdapter {
  static isAvailable(): boolean {
    return isHerdrAvailable();
  }

  static async listAgents(): Promise<HerdrAgentInfo[]> {
    if (!this.isAvailable()) return [];
    try {
      const res = await sendHerdrRequest<{ agents: HerdrAgentInfo[] }>("agent.list", {});
      return res?.agents ?? [];
    } catch (err) {
      console.log(`[herdr-adapter] listAgents error: ${String(err)}`);
      return [];
    }
  }

  static async readTerminal(
    target: string,
    lines = 100,
    format: "text" | "ansi" = "text",
  ): Promise<string> {
    if (!this.isAvailable()) return "";
    const res = await sendHerdrRequest<{ read?: { text?: string } }>("agent.read", {
      target,
      source: "recent",
      lines,
      format,
    });
    return res?.read?.text ?? "";
  }

  static async sendPrompt(target: string, text: string): Promise<void> {
    await sendHerdrRequest("agent.prompt", {
      target,
      text,
    });
  }

  static async sendKeys(target: string, keys: string[]): Promise<void> {
    await sendHerdrRequest("agent.send_keys", {
      target,
      keys,
    });
  }

  static async resolveSessionFile(paneId: string): Promise<{
    sessionPath?: string;
    sessionId?: string;
    agent: string;
    paneId: string;
    title?: string;
  } | null> {
    const targetPaneId = paneId.replace(/^herdr:/, "");
    const agents = await this.listAgents();
    const match = agents.find((a) => a.pane_id === targetPaneId);
    if (!match) return null;

    const targetCwd = match.foreground_cwd || match.cwd;
    let sessionPath: string | undefined;

    // Tier 1: Check active running process in this CWD
    if (targetCwd) {
      const activeFile = findActiveSessionFileForCwd(targetCwd);
      if (activeFile) {
        sessionPath = activeFile;
      }
    }

    // Tier 2: Check if Herdr reported path exists and matches cwd
    if (!sessionPath && match.agent_session?.kind === "path" && match.agent_session.value) {
      const candidate = match.agent_session.value;
      if (existsSync(candidate)) {
        if (!targetCwd || candidate.includes(path.basename(targetCwd))) {
          sessionPath = candidate;
        }
      }
    }

    // Tier 3: Find newest session in cwd session directory
    if (!sessionPath && targetCwd) {
      const sessionDir = findSessionDir(targetCwd);
      const newest = findNewestSessionInDir(sessionDir);
      if (newest) {
        sessionPath = newest;
      }
    }

    // Tier 4: Fall back to Herdr candidate if it exists
    if (!sessionPath && match.agent_session?.kind === "path" && match.agent_session.value) {
      if (existsSync(match.agent_session.value)) {
        sessionPath = match.agent_session.value;
      }
    }

    if (sessionPath) {
      const base = path.basename(sessionPath, ".jsonl");
      const parts = base.split("_");
      const sessionId = parts.length > 1 ? parts[parts.length - 1] : base;
      const fileTitle = readSessionTitle(sessionPath);
      return {
        sessionPath,
        sessionId,
        agent: match.agent,
        paneId: targetPaneId,
        title: fileTitle || match.terminal_title_stripped || match.terminal_title,
      };
    }

    return {
      agent: match.agent,
      paneId: targetPaneId,
      title: match.terminal_title_stripped || match.terminal_title,
    };
  }
}

// ── Streamer & Output Delta Synchronizer ──────────────────────────────

interface StreamSession {
  paneId: string;
  lastContent: string;
  lastStatus: string;
  subscribers: Set<(msg: unknown) => void>;
  timer: NodeJS.Timeout | null;
  pollCount: number;
}

const activeStreams = new Map<string, StreamSession>();

export class HerdrStreamer {
  /**
   * Subscribe a client callback to live updates of a Herdr pane.
   */
  static subscribe(paneId: string, listener: (msg: unknown) => void): void {
    let sess = activeStreams.get(paneId);
    if (!sess) {
      sess = {
        paneId,
        lastContent: "",
        lastStatus: "unknown",
        subscribers: new Set(),
        timer: null,
        pollCount: 0,
      };
      activeStreams.set(paneId, sess);
      this.startPolling(sess);
    }
    sess.subscribers.add(listener);
  }

  /**
   * Unsubscribe a client callback. Automatically cleans up timer and memory when subscribers reach 0.
   */
  static unsubscribe(paneId: string, listener: (msg: unknown) => void): void {
    const sess = activeStreams.get(paneId);
    if (!sess) return;
    sess.subscribers.delete(listener);
    if (sess.subscribers.size === 0) {
      if (sess.timer) {
        clearInterval(sess.timer);
        sess.timer = null;
      }
      activeStreams.delete(paneId);
      console.log(`[herdr-streamer] stopped watching pane ${paneId} (no subscribers)`);
    }
  }

  /**
   * Seed the initial content of a session so first poll only computes new deltas.
   */
  static seedContent(paneId: string, initialContent: string): void {
    const sess = activeStreams.get(paneId);
    if (sess) {
      sess.lastContent = initialContent;
    }
  }

  private static startPolling(sess: StreamSession): void {
    const pollInterval = 300; // 300ms 黄金刷新率，平滑流畅且不占用 CPU
    sess.timer = setInterval(async () => {
      if (sess.subscribers.size === 0) {
        if (sess.timer) clearInterval(sess.timer);
        activeStreams.delete(sess.paneId);
        return;
      }

      try {
        const raw = await HerdrAdapter.readTerminal(sess.paneId, 100, "text");
        const text = cleanTerminalText(raw);
        if (sess.lastContent === "") {
          sess.lastContent = text;
        } else if (text !== sess.lastContent) {
          const delta = computeTerminalDelta(sess.lastContent, text);

          if (delta.length > 0 && delta.trim().length > 0) {
            sess.lastContent = text;
            const eventMsg = {
              type: "agent_event",
              sessionId: `herdr:${sess.paneId}`,
              event: {
                sessionUpdate: "agent_message_chunk",
                content: {
                  type: "text",
                  text: delta,
                },
              },
            };
            for (const sub of sess.subscribers) {
              try {
                sub(eventMsg);
              } catch {
                // ignore failed subscriber
              }
            }
          }
        }

        // Check status change every 4 polls (2 seconds)
        sess.pollCount += 1;
        if (sess.pollCount % 4 === 0) {
          const agents = await HerdrAdapter.listAgents();
          const info = agents.find((a) => a.pane_id === sess.paneId);
          if (info && info.agent_status !== sess.lastStatus) {
            const oldStatus = sess.lastStatus;
            sess.lastStatus = info.agent_status;
            if (oldStatus === "working" && (info.agent_status === "idle" || info.agent_status === "done")) {
              const turnEndMsg = {
                type: "turn_ended",
                sessionId: `herdr:${sess.paneId}`,
              };
              for (const sub of sess.subscribers) {
                try {
                  sub(turnEndMsg);
                } catch { /* ok */ }
              }
            }
          }
        }
      } catch (err) {
        // Silent error on individual poll cycle
      }
    }, pollInterval);
  }
}

/**
 * Cleans ANSI escape codes and raw carriage returns from terminal output.
 */
export function cleanTerminalText(str: string): string {
  return str
    .replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "")
    .replace(/\x1b\].*?(\x07|\x1b\\)/g, "")
    .replace(/\r/g, "");
}

/**
 * Computes new appended text using high-performance line-based diff.
 */
export function computeTerminalDelta(oldText: string, newText: string): string {
  if (!oldText) return newText;
  if (newText === oldText) return "";
  if (newText.startsWith(oldText)) {
    return newText.slice(oldText.length);
  }

  const oldLines = oldText.split("\n");
  const newLines = newText.split("\n");

  let matchIdx = 0;
  const maxCheck = Math.min(oldLines.length, newLines.length);
  while (matchIdx < maxCheck && oldLines[matchIdx] === newLines[matchIdx]) {
    matchIdx++;
  }

  if (matchIdx < newLines.length) {
    if (matchIdx > 0 && matchIdx === oldLines.length && newLines[matchIdx - 1]?.startsWith(oldLines[matchIdx - 1])) {
      const partial = newLines[matchIdx - 1].slice(oldLines[matchIdx - 1].length);
      const remaining = newLines.slice(matchIdx).join("\n");
      return partial + (remaining ? "\n" + remaining : "");
    }
    return newLines.slice(matchIdx).join("\n");
  }

  return "";
}

function findActiveSessionFileForCwd(targetCwd: string): string | null {
  try {
    const pids = execSync('pgrep -f "bun .*/omp"', { encoding: "utf8" }).trim().split("\n").filter(Boolean);
    const resolvedTarget = realpathSync(targetCwd);

    for (const pid of pids) {
      try {
        const procCwd = realpathSync(`/proc/${pid}/cwd`);
        if (procCwd === resolvedTarget) {
          const fds = readdirSync(`/proc/${pid}/fd`);
          for (const fd of fds) {
            try {
              const link = readlinkSync(`/proc/${pid}/fd/${fd}`);
              if (link.endsWith(".jsonl") && existsSync(link)) {
                return link;
              }
            } catch {}
          }
        }
      } catch {}
    }
  } catch {}
  return null;
}

function findSessionDir(cwd: string): string | null {
  const baseDir = path.join(homedir(), ".omp", "agent", "sessions");
  if (!existsSync(baseDir)) return null;
  const dirs = readdirSync(baseDir);
  const norm = path.resolve(cwd);
  for (const d of dirs) {
    const cleaned = d.replace(/^-+|-+$/g, "").replace(/-/g, "/");
    if ("/" + cleaned === norm || cleaned === norm.replace(/^\//, "")) {
      return path.join(baseDir, d);
    }
  }
  return null;
}

function findNewestSessionInDir(dir: string | null): string | null {
  if (!dir || !existsSync(dir)) return null;
  const files = readdirSync(dir).filter((f) => f.endsWith(".jsonl"));
  if (files.length === 0) return null;
  files.sort((a, b) => statSync(path.join(dir, b)).mtimeMs - statSync(path.join(dir, a)).mtimeMs);
  return path.join(dir, files[0]);
}

export function readSessionTitle(filePath: string): string | null {
  try {
    const content = readFileSync(filePath, "utf8");
    const lines = content.split("\n");
    let title: string | null = null;
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const obj = JSON.parse(line);
        if (obj.type === "title" || obj.type === "title_change") {
          title = obj.title;
        }
      } catch {}
    }
    return title;
  } catch {
    return null;
  }
}

export function findSessionFileById(sessionId: string): string | null {
  const baseDir = path.join(homedir(), ".omp", "agent", "sessions");
  if (!existsSync(baseDir)) return null;
  try {
    const dirs = readdirSync(baseDir);
    for (const d of dirs) {
      const dirPath = path.join(baseDir, d);
      try {
        if (!statSync(dirPath).isDirectory()) continue;
        const files = readdirSync(dirPath);
        for (const f of files) {
          if (f.endsWith(".jsonl") && f.includes(sessionId)) {
            return path.join(dirPath, f);
          }
        }
      } catch {}
    }
  } catch {}
  return null;
}
