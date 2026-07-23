#!/usr/bin/env node

import { spawn } from 'child_process';
import { openSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import { startDaemon, stopDaemon, getDaemonStatus } from './daemon/bootstrap.mjs';

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

function parsePortFromArgs(args: string[]): number {
  for (const arg of args) {
    if (arg.startsWith('--port=')) {
      const value = arg.split('=')[1];
      const port = parseInt(value, 10);
      if (!isNaN(port) && port > 0 && port <= 65535) {
        return port;
      }
      console.error(`[nexus] Invalid port: ${value}`);
      process.exit(1);
    }
  }
  return 12138;
}

async function main(): Promise<void> {
  const command = process.argv[2];
  const args = process.argv.slice(3);

  switch (command) {
    case 'start': {
      const port = parsePortFromArgs(args);
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
      const port = parsePortFromArgs(args);
      await stopDaemon();
      // Wait for shutdown to complete (poll /health until unreachable)
      for (let i = 0; i < 10; i++) {
        await new Promise((resolve) => setTimeout(resolve, 500));
        try {
          const res = await fetch(`http://127.0.0.1:${port}/health`);
          if (!res.ok) break;
        } catch {
          break; // Daemon stopped
        }
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
