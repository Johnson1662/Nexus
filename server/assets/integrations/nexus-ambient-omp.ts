// installed by nexus
// managed by nexus; updating overwrites this file.
// NEXUS_AMBIENT_INTEGRATION_VERSION=1
// @ts-nocheck

import net from "node:net";
import path from "node:path";
import { homedir } from "node:os";
import { existsSync, mkdirSync, writeFileSync, renameSync, unlinkSync, chmodSync } from "node:fs";
import { randomBytes } from "node:crypto";

// Avoid dual-registration when running under Herdr
if (process.env.HERDR_ENV === "1") {
  // Herdr handles its own session reporting
  // Do not register ambient extension
}

function getNexusDataDir(): string {
  const env = process.env.NEXUS_DATA_DIR?.trim();
  return env ? path.resolve(env) : path.join(homedir(), ".nexus");
}

function getAmbientRuntimeDir(): string {
  return path.join(getNexusDataDir(), "ambient");
}

function getSessionsDir(): string {
  return path.join(getAmbientRuntimeDir(), "sessions");
}

function ensureSessionsDir(): string {
  const dir = getSessionsDir();
  mkdirSync(dir, { recursive: true });
  if (process.platform !== "win32") {
    try {
      chmodSync(getAmbientRuntimeDir(), 0o700);
      chmodSync(dir, 0o700);
    } catch {}
  }
  return dir;
}

export default function (pi) {
  if (process.env.HERDR_ENV === "1") {
    return;
  }

  let currentCtx = null;
  let currentSessionId = "";
  let currentTranscriptPath = "";
  let currentStatus = "idle";
  let heartbeatTimer = null;
  let tcpPort = 0;
  let server = null;
  const controlToken = randomBytes(32).toString("hex");

  function writeClaim(): void {
    if (!currentSessionId || !currentTranscriptPath || !tcpPort) {
      return;
    }
    try {
      const dir = ensureSessionsDir();
      const targetFile = path.join(dir, `${currentSessionId}.json`);
      const tmpFile = path.join(
        dir,
        `.${currentSessionId}.${process.pid}.${Date.now()}.${Math.random().toString(36).slice(2, 8)}.tmp`,
      );
      const payload = {
        version: 1,
        agent: "omp",
        sessionId: currentSessionId,
        pid: process.pid,
        cwd: process.cwd(),
        transcriptPath: currentTranscriptPath,
        status: currentStatus,
        updatedAt: Date.now(),
        control: {
          host: "127.0.0.1",
          port: tcpPort,
          token: controlToken,
        },
      };
      writeFileSync(tmpFile, JSON.stringify(payload, null, 2), "utf8");
      renameSync(tmpFile, targetFile);
    } catch (err) {
      // Best-effort file sync
    }
  }

  function removeClaim(sessionId?: string): void {
    const id = sessionId || currentSessionId;
    if (!id) return;
    try {
      const targetFile = path.join(getSessionsDir(), `${id}.json`);
      if (existsSync(targetFile)) {
        unlinkSync(targetFile);
      }
    } catch {}
  }

  function startControlServer(): void {
    server = net.createServer((socket) => {
      let buffer = "";
      socket.on("data", (chunk) => {
        buffer += chunk.toString("utf8");
        if (buffer.length > 64 * 1024) {
          socket.destroy();
          return;
        }
        let newlineIndex: number;
        while ((newlineIndex = buffer.indexOf("\n")) !== -1) {
          const line = buffer.slice(0, newlineIndex).trim();
          buffer = buffer.slice(newlineIndex + 1);
          if (!line) continue;
          handleCommand(line, socket);
        }
      });
      socket.on("error", () => {});
    });

    server.listen(0, "127.0.0.1", () => {
      const addr = server?.address();
      if (addr && typeof addr === "object") {
        tcpPort = addr.port;
        writeClaim();
      }
    });

    server.on("error", () => {});
  }

  function handleCommand(line: string, socket: net.Socket): void {
    try {
      const msg = JSON.parse(line);
      if (!msg || typeof msg !== "object" || msg.token !== controlToken) {
        socket.write(JSON.stringify({ ok: false, error: "unauthorized" }) + "\n");
        return;
      }
      if (msg.type === "prompt") {
        const text = typeof msg.text === "string" ? msg.text.trim() : "";
        if (!text) {
          socket.write(JSON.stringify({ ok: false, error: "empty prompt" }) + "\n");
          return;
        }
        if (typeof pi.sendUserMessage === "function") {
          pi.sendUserMessage(text);
          socket.write(JSON.stringify({ ok: true }) + "\n");
        } else {
          socket.write(JSON.stringify({ ok: false, error: "sendUserMessage not supported" }) + "\n");
        }
        return;
      }
      if (msg.type === "cancel") {
        if (currentCtx && typeof currentCtx.abort === "function") {
          currentCtx.abort();
          socket.write(JSON.stringify({ ok: true }) + "\n");
        } else {
          socket.write(JSON.stringify({ ok: false, error: "session context unavailable" }) + "\n");
        }
        return;
      }
      if (msg.type === "ping") {
        socket.write(JSON.stringify({ ok: true, status: currentStatus, pid: process.pid }) + "\n");
        return;
      }
      socket.write(JSON.stringify({ ok: false, error: "unknown command" }) + "\n");
    } catch {
      socket.write(JSON.stringify({ ok: false, error: "invalid json" }) + "\n");
    }
  }

  function updateSessionInfo(ctx: unknown): void {
    if (ctx) {
      currentCtx = ctx as {
        abort?: () => void;
        setInterval?: (cb: () => void, ms?: number) => NodeJS.Timeout;
        sessionManager?: {
          getSessionFile?: () => string;
          getSessionId?: () => string;
        };
      };
    }
    try {
      const file = currentCtx?.sessionManager?.getSessionFile?.();
      if (typeof file === "string" && file.length > 0 && path.isAbsolute(file)) {
        currentTranscriptPath = file;
      }
    } catch {}
    try {
      const id = currentCtx?.sessionManager?.getSessionId?.();
      if (typeof id === "string" && id.length > 0) {
        currentSessionId = id;
      }
    } catch {}
  }

  function ensureHeartbeat(ctx: unknown): void {
    if (heartbeatTimer) return;
    const targetCtx = (ctx || currentCtx) as { setInterval?: (cb: () => void, ms?: number) => NodeJS.Timeout } | null;
    const intervalFn = targetCtx && typeof targetCtx.setInterval === "function"
      ? targetCtx.setInterval.bind(targetCtx)
      : setInterval;
    heartbeatTimer = intervalFn(() => {
      writeClaim();
    }, 5000);
  }

  // Lifecycle registrations
  pi.on("session_start", (_event, ctx) => {
    updateSessionInfo(ctx);
    currentStatus = "idle";
    ensureHeartbeat(ctx);
    writeClaim();
  });

  pi.on("session_switch", (event, ctx) => {
    const oldId = currentSessionId;
    updateSessionInfo(ctx);
    currentStatus = "idle";
    if (oldId && oldId !== currentSessionId) {
      removeClaim(oldId);
    }
    ensureHeartbeat(ctx);
    writeClaim();
  });

  pi.on("agent_start", (_event, ctx) => {
    updateSessionInfo(ctx);
    currentStatus = "working";
    writeClaim();
  });

  pi.on("agent_end", () => {
    currentStatus = "idle";
    writeClaim();
  });

  pi.on("tool_approval_requested", () => {
    currentStatus = "blocked";
    writeClaim();
  });

  pi.on("tool_approval_resolved", () => {
    currentStatus = "working";
    writeClaim();
  });

  pi.on("session_shutdown", () => {
    removeClaim();
    if (server) {
      try {
        server.close();
      } catch {}
      server = null;
    }
    currentCtx = null;
    currentSessionId = "";
    currentTranscriptPath = "";
  });

  process.on("exit", () => {
    removeClaim();
  });

  // Start local loopback server immediately on load
  startControlServer();
}
