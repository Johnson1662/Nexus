#!/usr/bin/env node

import { spawn } from 'child_process';
import { connect } from 'node:net';
import { openSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import { startDaemon, stopDaemon, getDaemonStatus } from './daemon/bootstrap.mjs';
import { isDaemonRunning, readDaemonLock } from './daemon/pid-lock.mjs';

function printUsage(): void {
  console.log(`Usage: nexus <command> [options]

Commands:
  start   [--port=N] [--foreground]  Start the daemon (default: background, port 12138)
  stop                Stop the running daemon
  restart [--port=N]  Restart the daemon
  status              Query daemon status

Options:
  --port=N       TCP port for the WebSocket server (default: 12138)
  --foreground   Run in foreground (default: background daemon)`);
}

function parsePortFromArgs(args: string[]): { port: number; explicit: boolean } {
  for (const arg of args) {
    if (arg.startsWith('--port=')) {
      const value = arg.split('=')[1];
      const port = parseInt(value, 10);
      if (!isNaN(port) && port > 0 && port <= 65535) {
        return { port, explicit: true };
      }
      console.error(`[nexus] Invalid port: ${value}`);
      process.exit(1);
    }
  }
  return { port: 12138, explicit: false };
}

/** TCP 连通性探测：成功连上即视为端口仍在监听。 */
function tcpReachable(port: number, host = '127.0.0.1'): Promise<boolean> {
  return new Promise((resolve) => {
    const sock = connect({ port, host });
    sock.setTimeout(500);
    sock.once('connect', () => { sock.destroy(); resolve(true); });
    sock.once('error', () => resolve(false));
    sock.once('timeout', () => { sock.destroy(); resolve(false); });
  });
}

async function main(): Promise<void> {
  const command = process.argv[2];
  const args = process.argv.slice(3);

  switch (command) {
    case 'start': {
      const { port } = parsePortFromArgs(args);
      const isForeground = args.indexOf('--foreground') >= 0;

      if (isForeground) {
        await startDaemon({ port });
      } else {
        // Fork to background
        const logDir = join(homedir(), '.nexus');
        const logFile = join(logDir, 'daemon.log');
        mkdirSync(logDir, { recursive: true });
        const fd = openSync(logFile, 'a');

        const child = spawn(process.execPath, [
          process.argv[1], 'start', '--foreground', `--port=${port}`
        ], {
          detached: true,
          stdio: ['ignore', fd, fd],
          windowsHide: true,
        });
        child.unref();
        console.log(`[nexus] Daemon started in background (pid: ${child.pid})`);
        process.exit(0);
      }
      break;
    }

    case 'stop': {
      await stopDaemon();
      break;
    }

    case 'status': {
      const status = await getDaemonStatus();
      if (status === null) {
        console.log('Daemon not running');
        process.exit(0);
      }
      console.log(JSON.stringify(status, null, 2));
      process.exit(0);
      break;
    }

    case 'restart': {
      const { port: explicitPort, explicit } = parsePortFromArgs(args);
      const LOCK_FILE = join(homedir(), '.nexus', 'daemon.lock');
      const CONTROL_PORT_FILE = join(homedir(), '.nexus', 'daemon.control.port');
      // 未显式指定 --port 时沿用当前 daemon 的 Bridge 端口（lock 文件），不重置为默认 12138
      let port = explicitPort;
      if (!explicit) {
        try {
          const lock = await readDaemonLock(LOCK_FILE);
          if (lock && lock.port > 0) port = lock.port;
        } catch { /* 无 lock：保持默认 */ }
      }
      // 先读控制端口：daemon 清理任务会在 shutdown 时删除 daemon.control.port
      let controlPort = 0;
      try {
        const { readFile } = await import('fs/promises');
        controlPort = parseInt((await readFile(CONTROL_PORT_FILE, 'utf-8')).trim(), 10);
      } catch { /* no control port file — skip polling */ }
      const stopped = await stopDaemon();
      if (!stopped) {
        throw new Error('failed to stop daemon — aborting restart');
      }
      // 等待完全关闭：Control Server 不可访问 + PID lock 已释放 + Bridge 端口已关闭
      const deadline = Date.now() + 10_000;
      let fullyStopped = false;
      while (Date.now() < deadline) {
        let controlUp = false;
        if (controlPort > 0) {
          try {
            const res = await fetch(`http://127.0.0.1:${controlPort}/health`);
            controlUp = res.ok;
          } catch {
            controlUp = false;
          }
        }
        const lockHeld = await isDaemonRunning(LOCK_FILE);
        const bridgeUp = await tcpReachable(port);
        if (!controlUp && !lockHeld && !bridgeUp) {
          fullyStopped = true;
          break;
        }
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
      if (!fullyStopped) {
        throw new Error('daemon did not stop within 10 seconds — aborting restart');
      }
      // Fork to background (same as start)
      const logDir = join(homedir(), '.nexus');
      const logFile = join(logDir, 'daemon.log');
      mkdirSync(logDir, { recursive: true });
      const fd = openSync(logFile, 'a');
      const child = spawn(process.execPath, [
        process.argv[1], 'start', '--foreground', `--port=${port}`
      ], {
        detached: true,
        stdio: ['ignore', fd, fd],
        windowsHide: true,
      });
      child.unref();
      console.log(`[nexus] Daemon restarted (pid: ${child.pid})`);
      process.exit(0);
      break;
    }

    default:
      printUsage();
      process.exit(1);
      break;
  }
}

main().catch((err: unknown) => {
  console.error('[nexus] Fatal error:', err);
  process.exit(1);
});
