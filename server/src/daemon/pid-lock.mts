import { open, readFile, unlink } from 'node:fs/promises';

export interface DaemonLockPayload {
  pid: number;
  port: number;
  startedAt: number;
}

/**
 * Tracks whether *this* process owns the daemon lock.
 * Reset on crash/restart since it is in-memory only.
 */
let ownsLock = false;

/**
 * Atomically acquire a PID-based daemon lock file using `'wx'` (O_EXCL).
 *
 * - Creates `lockFile` exclusively, writes the JSON payload.
 * - If `EEXIST`: reads the existing lock, checks if the PID is alive.
 *   - Alive → returns `false` (another daemon holds the lock).
 *   - Dead / unparseable → removes stale lock and retries (up to `maxAttempts`).
 * - Returns `true` if this process now owns the lock.
 */
export async function acquireDaemonLock(
  lockFile: string,
  payload: DaemonLockPayload,
  maxAttempts = 5,
): Promise<boolean> {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      // Atomic exclusive-create.  Fails with EEXIST if file already exists.
      const fd = await open(lockFile, 'wx', 0o600);
      try {
        await fd.writeFile(JSON.stringify(payload, null, 2), 'utf-8');
      } catch (writeErr) {
        // Write to the freshly-created file failed (disk full, etc.).
        // Clean up the empty file so we don't leave trash.
        await fd.close().catch(() => {});
        await unlink(lockFile).catch(() => {});
        return false;
      }
      await fd.close();
      ownsLock = true;
      return true;
    } catch (err: unknown) {
      const nodeErr = err as NodeJS.ErrnoException;
      if (nodeErr?.code !== 'EEXIST') {
        // Permission error or some other issue — cannot acquire.
        return false;
      }

      // ── Lock file already exists — check if stale ──
      try {
        const existing = await readDaemonLock(lockFile);
        if (existing) {
          try {
            // signal 0 = probe, does not actually signal the process
            process.kill(existing.pid, 0);
            // Process is alive — another daemon holds the lock.
            return false;
          } catch (killErr: unknown) {
            const killNodeErr = killErr as NodeJS.ErrnoException;
            if (killNodeErr?.code === 'ESRCH') {
              // Process is gone — stale lock.  Clean up and retry.
              await unlink(lockFile).catch(() => {});
              continue;
            }
            // EPERM or other unexpected error — treat the lock as alive.
            return false;
          }
        } else {
          // Lock file exists but payload is missing/unparseable — stale.
          await unlink(lockFile).catch(() => {});
          continue;
        }
      } catch {
        // Can't even read the file — treat as stale and retry.
        await unlink(lockFile).catch(() => {});
        continue;
      }
    }
  }
  return false;
}

/**
 * Release the daemon lock owned by this process.
 *
 * Only performs the unlink when `ownsLock` is `true`, so unrelated
 * processes cannot accidentally steal the lock.
 */
export async function releaseDaemonLock(lockFile: string): Promise<void> {
  if (!ownsLock) return;
  ownsLock = false;
  await unlink(lockFile).catch(() => {
    // Best-effort — the file may already have been cleaned up during
    // a forced shutdown sequence.
  });
}

/**
 * Read and parse the daemon lock file without side effects.
 *
 * Returns `null` when the file does not exist, is unreadable, or
 * contains invalid JSON / unexpected shape.
 */
export async function readDaemonLock(lockFile: string): Promise<DaemonLockPayload | null> {
  try {
    const data = await readFile(lockFile, 'utf-8');
    const parsed = JSON.parse(data);
    if (
      typeof parsed.pid === 'number' &&
      typeof parsed.port === 'number' &&
      typeof parsed.startedAt === 'number'
    ) {
      return parsed as DaemonLockPayload;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Check whether the daemon identified by `lockFile` is currently running.
 *
 * Returns `true` only when a valid lock exists *and* the recorded PID
 * is still alive (process existence check, signal 0).
 */
export async function isDaemonRunning(lockFile: string): Promise<boolean> {
  const payload = await readDaemonLock(lockFile);
  if (!payload) return false;
  try {
    process.kill(payload.pid, 0);
    return true;
  } catch {
    return false;
  }
}
