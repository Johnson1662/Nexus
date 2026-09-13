import net from "node:net";
import path from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
  renameSync,
  unlinkSync,
  watch,
  type FSWatcher,
} from "node:fs";
import { getAmbientRuntimeDir } from "../path-utils.mjs";

export interface AmbientSessionInfo {
  sessionId: string; // "ambient:omp:<uuid>"
  realSessionId: string; // "<uuid>"
  agent: "omp";
  pid: number;
  cwd: string;
  transcriptPath: string;
  status: "running" | "idle" | "waiting_input";
  updatedAt: number;
  control: {
    host: "127.0.0.1";
    port: number;
    token: string;
  };
}

interface RawAmbientClaim {
  version: number;
  agent: string;
  sessionId: string;
  pid: number;
  cwd: string;
  transcriptPath: string;
  status: "working" | "idle" | "blocked";
  updatedAt: number;
  control: {
    host: string;
    port: number;
    token: string;
  };
}

const STALE_TIMEOUT_MS = 15000;
const COMMAND_TIMEOUT_MS = 3000;
const CURRENT_INTEGRATION_VERSION = 1;

function getSessionsDir(): string {
  return path.join(getAmbientRuntimeDir(), "sessions");
}

function normalizeStatus(raw: "working" | "idle" | "blocked"): "running" | "idle" | "waiting_input" {
  if (raw === "working") return "running";
  if (raw === "blocked") return "waiting_input";
  return "idle";
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err: unknown) {
    const error = err as NodeJS.ErrnoException;
    return error.code === "EPERM";
  }
}

function parseAndValidateClaim(filePath: string, now: number = Date.now()): AmbientSessionInfo | null {
  try {
    if (!existsSync(filePath)) return null;
    const raw = readFileSync(filePath, "utf8");
    const data = JSON.parse(raw) as Partial<RawAmbientClaim>;

    if (
      data.version !== 1 ||
      data.agent !== "omp" ||
      typeof data.sessionId !== "string" ||
      !data.sessionId ||
      typeof data.pid !== "number" ||
      data.pid <= 0 ||
      typeof data.cwd !== "string" ||
      typeof data.transcriptPath !== "string" ||
      !path.isAbsolute(data.transcriptPath) ||
      !existsSync(data.transcriptPath) ||
      typeof data.updatedAt !== "number" ||
      !data.control ||
      data.control.host !== "127.0.0.1" ||
      typeof data.control.port !== "number" ||
      data.control.port <= 0 ||
      data.control.port > 65535 ||
      typeof data.control.token !== "string" ||
      !data.control.token
    ) {
      try { unlinkSync(filePath); } catch {}
      return null;
    }

    if (now - data.updatedAt > STALE_TIMEOUT_MS) {
      try { unlinkSync(filePath); } catch {}
      return null;
    }

    if (!isProcessAlive(data.pid)) {
      try { unlinkSync(filePath); } catch {}
      return null;
    }

    const rawStatus = data.status === "working" || data.status === "blocked" ? data.status : "idle";

    return {
      sessionId: `ambient:omp:${data.sessionId}`,
      realSessionId: data.sessionId,
      agent: "omp",
      pid: data.pid,
      cwd: data.cwd,
      transcriptPath: data.transcriptPath,
      status: normalizeStatus(rawStatus),
      updatedAt: data.updatedAt,
      control: {
        host: "127.0.0.1",
        port: data.control.port,
        token: data.control.token,
      },
    };
  } catch {
    try { unlinkSync(filePath); } catch {}
    return null;
  }
}

export function listAmbientSessions(): AmbientSessionInfo[] {
  const dir = getSessionsDir();
  if (!existsSync(dir)) return [];
  const entries = readdirSync(dir).filter((f) => f.endsWith(".json") && !f.startsWith("."));
  const now = Date.now();
  const sessions: AmbientSessionInfo[] = [];

  for (const entry of entries) {
    const fullPath = path.join(dir, entry);
    const session = parseAndValidateClaim(fullPath, now);
    if (session) {
      sessions.push(session);
    }
  }

  sessions.sort((a, b) => b.updatedAt - a.updatedAt);
  return sessions;
}

export function getAmbientSession(targetId: string): AmbientSessionInfo | null {
  if (!targetId) return null;
  const realId = targetId.startsWith("ambient:omp:")
    ? targetId.slice("ambient:omp:".length)
    : targetId.startsWith("ambient:")
      ? targetId.split(":").slice(2).join(":")
      : targetId;

  const claimFile = path.join(getSessionsDir(), `${realId}.json`);
  return parseAndValidateClaim(claimFile);
}

export async function sendAmbientCommand(
  sessionId: string,
  command: { type: "prompt"; text: string } | { type: "cancel" },
): Promise<void> {
  const session = getAmbientSession(sessionId);
  if (!session) {
    throw new Error(`ambient session not found: ${sessionId}`);
  }

  return new Promise<void>((resolve, reject) => {
    let settled = false;
    const socket = net.createConnection({
      host: session.control.host,
      port: session.control.port,
    });

    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      socket.destroy();
      reject(new Error("ambient command timed out"));
    }, COMMAND_TIMEOUT_MS);

    let buffer = "";
    socket.on("connect", () => {
      const payload = {
        ...command,
        token: session.control.token,
      };
      socket.write(JSON.stringify(payload) + "\n");
    });

    socket.on("data", (chunk) => {
      buffer += chunk.toString("utf8");
      const newlineIndex = buffer.indexOf("\n");
      if (newlineIndex !== -1) {
        const line = buffer.slice(0, newlineIndex).trim();
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        socket.end();
        try {
          const res = JSON.parse(line) as { ok?: boolean; error?: string };
          if (res && res.ok === true) {
            resolve();
          } else {
            reject(new Error(res?.error || "command rejected by agent"));
          }
        } catch {
          reject(new Error("invalid response from ambient control server"));
        }
      }
    });

    socket.on("error", (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(err);
    });
  });
}

export function watchAmbientSessions(onChange: () => void): () => void {
  const dir = getSessionsDir();
  mkdirSync(dir, { recursive: true });

  let watcher: FSWatcher | null = null;
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  let pollTimer: ReturnType<typeof setInterval> | null = null;
  let lastKnownKey = "";

  function trigger(): void {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      debounceTimer = null;
      const current = listAmbientSessions();
      const currentKey = current.map((s) => `${s.sessionId}:${s.status}:${s.updatedAt}`).join("|");
      if (currentKey !== lastKnownKey) {
        lastKnownKey = currentKey;
        onChange();
      }
    }, 300);
  }

  try {
    watcher = watch(dir, () => {
      trigger();
    });
    watcher.on("error", () => {});
  } catch {}

  pollTimer = setInterval(() => {
    trigger();
  }, 2000);

  return () => {
    if (debounceTimer) clearTimeout(debounceTimer);
    if (pollTimer) clearInterval(pollTimer);
    if (watcher) {
      try { watcher.close(); } catch {}
      watcher = null;
    }
  };
}

export function ensureOmpAmbientIntegration(): void {
  try {
    const targetDir = path.join(homedir(), ".omp", "agent", "extensions");
    const targetPath = path.join(targetDir, "nexus-ambient.ts");

    // Resolve source file relative to import.meta.url
    const currentDir = path.dirname(fileURLToPath(import.meta.url));
    const candidatePaths = [
      path.resolve(currentDir, "../integrations/nexus-ambient-omp.ts"),
      path.resolve(currentDir, "../../assets/integrations/nexus-ambient-omp.ts"),
      path.resolve(currentDir, "../assets/integrations/nexus-ambient-omp.ts"),
    ];

    const sourcePath = candidatePaths.find((p) => existsSync(p));
    if (!sourcePath) {
      console.log("[ambient] integration source asset not found, skipping auto-install");
      return;
    }

    const sourceContent = readFileSync(sourcePath, "utf8");

    if (existsSync(targetPath)) {
      const existing = readFileSync(targetPath, "utf8");
      if (!existing.includes("NEXUS_AMBIENT_INTEGRATION_VERSION=")) {
        console.log(`[ambient] user extension exists at ${targetPath} without management marker; preserving`);
        return;
      }
      const match = existing.match(/NEXUS_AMBIENT_INTEGRATION_VERSION=(\d+)/);
      const version = match ? parseInt(match[1], 10) : 0;
      if (version >= CURRENT_INTEGRATION_VERSION) {
        return;
      }
    }

    mkdirSync(targetDir, { recursive: true });
    const tmpPath = path.join(targetDir, `.nexus-ambient.${process.pid}.${Date.now()}.tmp`);
    writeFileSync(tmpPath, sourceContent, "utf8");
    try {
      const fsRename = renameSync;
      fsRename(tmpPath, targetPath);
    } catch {
      writeFileSync(targetPath, sourceContent, "utf8");
      try { unlinkSync(tmpPath); } catch {}
    }
    console.log(`[ambient] installed OMP ambient extension (v${CURRENT_INTEGRATION_VERSION}) to ${targetPath}`);
  } catch (err) {
    console.log(`[ambient] failed to ensure OMP ambient extension: ${String(err)}`);
  }
}
