import { spawn } from "node:child_process";
import { join } from "node:path";
import { homedir } from "node:os";
import { mkdirSync, existsSync, realpathSync, statSync } from "node:fs";
import type { RequestPermissionResponse } from "@agentclientprotocol/sdk";
import { AcpClient } from "./acp/client.mjs";
import { resolveAgentRuntime } from "./agents-store.mjs";
import { resolveNativeAcpLaunch } from "./discovery/acp-adapters.mjs";
import { resolveExplicitCwd } from "./path-utils.mjs";
/**
 * Creates a temporary ACP client + agent process for one-shot listing operations.
 * Call destroy() to clean up (kills process and closes connection).
 */
export async function createTempClient(
  agent: string,
  cwd?: string,
): Promise<{ client: AcpClient; destroy: () => void }> {
  const runtime = resolveAgentRuntime(agent);
  if (!runtime || !runtime.installed) {
    throw new Error(`agent is not installed: ${agent}`);
  }
  const launchRes = resolveNativeAcpLaunch(agent);
  if (!launchRes.ok) {
    throw new Error(launchRes.error);
  }
  const launch = launchRes.launch;
  if (!launch.cmd || launch.args.some((arg: unknown) => typeof arg !== "string")) {
    throw new Error(`invalid or unavailable agent: ${agent}`);
  }
  const ANYWHERE_DIR = join(homedir(), ".nexus");
  mkdirSync(ANYWHERE_DIR, { recursive: true, mode: 0o700 });
  // Same fail-closed rule as a real session: an explicit invalid cwd is an
  // error, never a silent switch to another directory.
  const resolvedCwd = resolveExplicitCwd(cwd, ANYWHERE_DIR);
  const proc = spawn(launch.cmd, launch.args, {
    cwd: resolvedCwd,
    env: { ...process.env, ...launch.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    windowsHide: true,
    shell: false,
  });

  proc.on("error", (err: Error) => {
    console.log(`[temp-client] spawn error: ${err.message}`);
  });

  proc.stderr?.on("data", (chunk: Buffer) => {
    console.log(`[temp-client] stderr: ${chunk.toString().slice(0, 200)}`);
  });

  const client = new AcpClient(proc, {
    onSessionUpdate: async () => {},
    onPermissionRequest: async (): Promise<RequestPermissionResponse> => ({
      outcome: { outcome: "cancelled" },
    }),
  });

  let timer: ReturnType<typeof setTimeout> | undefined;
  let rejectProcessError: (error: Error) => void = () => {};
  const onProcessError = (error: Error) => rejectProcessError(error);
  const processError = new Promise<never>((_resolve, reject) => {
    rejectProcessError = (error: Error) => reject(new Error(`agent process failed: ${error.message}`));
    proc.once("error", onProcessError);
  });
  const timeout = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new Error("agent initialize timeout")), 8_000);
  });
  try {
    await Promise.race([client.initialize(), processError, timeout]);
  } catch (error) {
    try { client.destroy(); } catch {}
    if (!proc.killed) {
      try { proc.kill("SIGTERM"); } catch {}
    }
    throw error;
  } finally {
    clearTimeout(timer);
    proc.removeListener("error", onProcessError);
  }

  return {
    client,
    destroy: () => {
      try { client.destroy(); } catch {}
      if (!proc.killed) {
        try { proc.kill("SIGTERM"); } catch {}
      }
    },
  };
}
