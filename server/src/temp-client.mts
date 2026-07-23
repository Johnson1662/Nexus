import { spawn } from "node:child_process";
import { join } from "node:path";
import { homedir } from "node:os";
import { mkdirSync } from "node:fs";
import { existsSync } from "node:fs";
import type { RequestPermissionResponse } from "@agentclientprotocol/sdk";
import { AcpClient } from "./acp/client.mjs";
import { getAgentLaunchArgs } from "./discovery/agents.mjs";
/**
 * Creates a temporary ACP client + agent process for one-shot listing operations.
 * Call destroy() to clean up (kills process and closes connection).
 */
export async function createTempClient(
  agent: string,
  cwd?: string,
): Promise<{ client: AcpClient; destroy: () => void }> {
  const args = getAgentLaunchArgs(agent);
  // cwd must exist, otherwise spawn with shell:true throws misleading ENOENT on cmd.exe
  const ANYWHERE_DIR = join(homedir(), '.anywhere');
  mkdirSync(ANYWHERE_DIR, { recursive: true });
  const resolvedCwd = cwd && existsSync(cwd) ? cwd : ANYWHERE_DIR;
  const proc = spawn(agent, args, {
    cwd: resolvedCwd,
    env: { ...process.env, FORCE_COLOR: "0", NO_COLOR: "1" },
    stdio: ["pipe", "pipe", "pipe"],
    windowsHide: true,
    shell: true,
  });

  proc.on("error", (err: Error) => {
    console.log(`[temp-client] spawn error: ${err.message}`);
  });

  proc.stderr!.on("data", (chunk: Buffer) => {
    console.log(`[temp-client] stderr: ${chunk.toString().slice(0, 200)}`);
  });

  const client = new AcpClient(proc, {
    onSessionUpdate: async () => {},
    onPermissionRequest: async (): Promise<RequestPermissionResponse> => ({ outcome: "approved" as any }),
  });

  await client.initialize();

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
