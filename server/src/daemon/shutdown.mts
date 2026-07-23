/**
 * Graceful daemon shutdown controller.
 * Promise-based signal handling: installs handlers on creation,
 * single-fire shutdown trigger, parallel cleanup with timeout.
 */
import process from "node:process";

export interface DaemonShutdownController {
  /** Call to request graceful shutdown with a source reason. */
  requestShutdown: (source: string) => void;
  /** Resolves with the source reason when shutdown is requested. */
  resolvesWhenShutdownRequested: Promise<string>;
  /** Whether shutdown has been initiated. */
  isShuttingDown: () => boolean;
  /** Register a cleanup task — must resolve within timeout. */
  registerCleanupTask: (task: () => Promise<void>) => void;
  /** Run all cleanup tasks in parallel with timeout. Removes signal handlers. */
  executeCleanup: (timeoutMs?: number) => Promise<void>;
}

export function createDaemonShutdownController(): DaemonShutdownController {
  let shuttingDown = false;
  let resolveShutdown: (reason: string) => void = () => {};
  const shutdownPromise = new Promise<string>((resolve) => {
    resolveShutdown = resolve;
  });
  const cleanupTasks: Array<() => Promise<void>> = [];

  function requestShutdown(source: string): void {
    if (shuttingDown) return;
    shuttingDown = true;
    resolveShutdown(source);
  }

  function isShuttingDown(): boolean {
    return shuttingDown;
  }

  function registerCleanupTask(task: () => Promise<void>): void {
    cleanupTasks.push(task);
  }

  async function executeCleanup(timeoutMs = 10_000): Promise<void> {
    process.off("SIGINT", onSigInt);
    process.off("SIGTERM", onSigTerm);
    process.off("uncaughtException", onUncaughtException);
    process.off("unhandledRejection", onUnhandledRejection);

    if (cleanupTasks.length === 0) return;

    const timeoutSignal = Symbol("timeout");
    const results = await Promise.allSettled(
      cleanupTasks.map((task) =>
        Promise.race([
          task(),
          new Promise<typeof timeoutSignal>((resolve) =>
            setTimeout(() => resolve(timeoutSignal), timeoutMs)
          ),
        ])
      )
    );

    for (const r of results) {
      if (r.status === "rejected" || r.value === timeoutSignal) {
        console.error(
          "[shutdown] cleanup %s: %s",
          r.status === "rejected" ? "error" : "timeout",
          r.status === "rejected" ? r.reason : `exceeded ${timeoutMs}ms`
        );
      }
    }
  }

  function onSigInt(): void {
    console.log("\n[shutdown] received SIGINT, initiating graceful shutdown...");
    requestShutdown("os-signal");
  }

  function onSigTerm(): void {
    console.log("[shutdown] received SIGTERM, initiating graceful shutdown...");
    requestShutdown("os-signal");
  }

  function onUncaughtException(err: Error): void {
    console.error("[shutdown] uncaught exception:", err);
    requestShutdown("exception");
  }

  function onUnhandledRejection(reason: unknown): void {
    console.error("[shutdown] unhandled rejection:", reason);
    requestShutdown("exception");
  }

  process.on("SIGINT", onSigInt);
  process.on("SIGTERM", onSigTerm);
  process.on("uncaughtException", onUncaughtException);
  process.on("unhandledRejection", onUnhandledRejection);

  return {
    requestShutdown,
    resolvesWhenShutdownRequested: shutdownPromise,
    isShuttingDown,
    registerCleanupTask,
    executeCleanup,
  };
}
