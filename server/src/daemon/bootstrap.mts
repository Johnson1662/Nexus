/**
 * Daemon bootstrap — managed daemon lifecycle for Nexus Bridge.
 *
 * Usage (via cli.mjs):
 *   nexus start   → startDaemon({ port })
 *   nexus stop    → stopDaemon()
 *   nexus status  → getDaemonStatus()
 */

import { homedir } from "os";
import { join, dirname } from "path";
import { mkdirSync, chmodSync } from "fs";
import { randomUUID } from "crypto";
import http from "http";
import { createBridgeServer } from "../server.mjs";
import {
  acquireDaemonLock,
  releaseDaemonLock,
  readDaemonLock,
  isDaemonRunning,
} from "./pid-lock.mjs";
import { createDaemonShutdownController } from "./shutdown.mjs";
import { startControlServer } from "./control-server.mjs";
import { sessionManager } from "../session-manager.mjs";
import type { DaemonLockPayload } from "./pid-lock.mjs";

// ── Paths ─────────────────────────────────────────────────────────

const DATA_DIR = join(homedir(), ".nexus");
const LOCK_FILE = join(DATA_DIR, "daemon.lock");
const PORT_FILE = join(DATA_DIR, "daemon.port");
const TOKEN_FILE = join(DATA_DIR, "daemon.token");

function ensureDataDir(): void {
  mkdirSync(DATA_DIR, { recursive: true });
}

// ── Types ─────────────────────────────────────────────────────────

export interface DaemonStartConfig {
  port: number;
}

export interface DaemonStatus {
  pid: number;
  port: number;
  uptime: number;
  activeSessions: number;
}

// ── startDaemon — main daemon entry point ─────────────────────────

export async function startDaemon(config: DaemonStartConfig): Promise<void> {
  ensureDataDir();

  const shutdown = createDaemonShutdownController();

  // 1. Acquire PID lock (atomic 'wx')
  const payload = { pid: process.pid, port: config.port, startedAt: Date.now() };
  const acquired = await acquireDaemonLock(LOCK_FILE, payload);
  if (!acquired) {
    const existing = await readDaemonLock(LOCK_FILE);
    if (existing) {
      console.log(`[nexus] Daemon already running (pid: ${existing.pid}, port: ${existing.port})`);
    } else {
      console.log("[nexus] Daemon already running (lock held)");
    }
    process.exit(0);
  }

  // 2. Write control data
  const daemonToken = randomUUID();
  const startedAt = Date.now();
  chmodSync(DATA_DIR, 0o700);
  // Write token so cli.mjs can authenticate
  import('fs/promises').then(fs => fs.writeFile(TOKEN_FILE, daemonToken, 'utf-8')).catch(() => {});

  // 3. Create bridge server (HTTP + WebSocket)
  console.log(`[nexus] Starting bridge server on port ${config.port}...`);
  const app = createBridgeServer({ port: config.port });

  // 4. Start IPC control server on 127.0.0.1:random
  console.log("[nexus] Starting control server...");
  const ctrl = await startControlServer({
    daemonToken,
    requestShutdown: (source: string) => {
      console.log(`[nexus] Shutdown requested via ${source}`);
      shutdown.requestShutdown(source);
    },
    getStatus: () => ({
      pid: process.pid,
      port: config.port,
      uptime: Math.floor((Date.now() - startedAt) / 1000),
      activeSessions: sessionManager.getActiveSessionIds().size,
    }),
  });

  // 5. Save control port for stopDaemon
  const { writeFile } = await import('fs/promises');
  const CONTROL_PORT_FILE = join(DATA_DIR, 'daemon.control.port');
  await writeFile(CONTROL_PORT_FILE, String(ctrl.port), 'utf-8');

  // 6. Register cleanup tasks
  shutdown.registerCleanupTask(async () => {
    console.log("[nexus] Stopping bridge server...");
    await app.stop();
  });
  shutdown.registerCleanupTask(async () => {
    console.log("[nexus] Releasing PID lock...");
    await releaseDaemonLock(LOCK_FILE);
  });
  shutdown.registerCleanupTask(async () => {
    console.log("[nexus] Closing control server...");
    try {
      await new Promise<void>((resolve) => ctrl.server.close(() => resolve()));
    } catch { /* already closed */ }
    try {
      const { rm } = await import('fs/promises');
      await rm(CONTROL_PORT_FILE, { force: true });
    } catch { /* ignore */ }
  });

  // 6. Log success
  console.log(`[nexus] Daemon started (pid: ${process.pid})`);
  console.log(`[nexus] Bridge listening on ws://0.0.0.0:${config.port}`);
  console.log(`[nexus] Control server on 127.0.0.1:${ctrl.port}`);

  // 7. Wait for shutdown signal
  const reason = await shutdown.resolvesWhenShutdownRequested;
  console.log(`[nexus] Shutting down (reason: ${reason})...`);

  // 8. Execute cleanup with 5s timeout
  await shutdown.executeCleanup(5000);
  console.log("[nexus] Daemon stopped");
}

// ── stopDaemon — send stop signal to running daemon via control server ──

export async function stopDaemon(port?: number): Promise<void> {
  // Find control port from saved file
  const CONTROL_PORT_FILE = join(DATA_DIR, 'daemon.control.port');
  let controlPort: number | null = null;
  try {
    const { readFile } = await import('fs/promises');
    const content = await readFile(CONTROL_PORT_FILE, 'utf-8');
    controlPort = parseInt(content.trim(), 10);
  } catch {
    // fall through
  }

  // Fall back to bridge port from lock file
  if (!controlPort) {
    const lock = await readDaemonLock(LOCK_FILE);
    if (lock) {
      controlPort = lock.port;
    } else {
      console.log('[nexus] No running daemon found');
      return;
    }
  }

  if (!port) port = controlPort;

  // Read token for auth
  let token = '';
  try {
    const { readFile } = await import('fs/promises');
    token = (await readFile(TOKEN_FILE, 'utf-8')).trim();
  } catch {
    // Token file may not exist — try without auth
  }

  // Send stop request
  const options: http.RequestOptions = {
    hostname: "127.0.0.1",
    port,
    path: "/stop",
    method: "POST",
    headers: token
      ? { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }
      : { "Content-Type": "application/json" },
  };

  return new Promise<void>((resolve) => {
    const req = http.request(options, (res) => {
      if (res.statusCode === 200) {
        console.log("[nexus] Stop signal sent");
      } else if (res.statusCode === 401) {
        console.error("[nexus] Stop rejected: unauthorized");
      } else {
        console.log(`[nexus] Unexpected response: ${res.statusCode}`);
      }
      resolve();
    });
    req.on("error", (err) => {
      console.error(`[nexus] Failed to send stop: ${err.message}`);
      resolve();
    });
    req.end("{}");
  });
}

// ── getDaemonStatus — check if daemon is running ──────────────────

export async function getDaemonStatus(): Promise<DaemonStatus | null> {
  const running = await isDaemonRunning(LOCK_FILE);
  if (!running) {
    return null;
  }

  const lock = await readDaemonLock(LOCK_FILE);
  if (!lock) {
    return null;
  }

  // Try to get health/status from control server
  // 统一走 daemon.control.port 的 /status（bridge 端口没有 /health）
  const CONTROL_PORT_FILE = join(DATA_DIR, 'daemon.control.port');
  try {
    const { readFile } = await import('fs/promises');
    const content = await readFile(CONTROL_PORT_FILE, 'utf-8');
    const controlPort = parseInt(content.trim(), 10);
    if (Number.isFinite(controlPort)) {
      const res = await fetch(`http://127.0.0.1:${controlPort}/status`);
      if (res.ok) {
        const data = await res.json();
        return {
          pid: lock.pid,
          port: controlPort,
          uptime: data.uptime || 0,
          activeSessions: data.activeSessions || 0,
        };
      }
    }
  } catch {
    // Control server may not respond; return basic info from lock
  }

  return {
    pid: lock.pid,
    port: lock.port,
    uptime: Math.floor((Date.now() - lock.startedAt) / 1000),
    activeSessions: 0,
  };
}
