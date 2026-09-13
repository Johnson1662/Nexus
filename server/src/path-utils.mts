import { homedir } from "node:os";
import path from "node:path";
import { mkdirSync, chmodSync } from "node:fs";

export function resolveWorkspacePath(cwd?: string): string | undefined {
  if (!cwd || !cwd.trim()) return undefined;
  const expanded = cwd.trim().replace(/^~(?=$|[\\/])/, homedir());
  return path.resolve(expanded);
}

export function getNexusDataDir(): string {
  const env = process.env.NEXUS_DATA_DIR?.trim();
  return env ? path.resolve(env) : path.join(homedir(), ".nexus");
}

export function getAmbientRuntimeDir(): string {
  return path.join(getNexusDataDir(), "ambient");
}

export function ensureAmbientRuntimeDir(): string {
  const dir = getAmbientRuntimeDir();
  const sessionsDir = path.join(dir, "sessions");
  mkdirSync(sessionsDir, { recursive: true });
  if (process.platform !== "win32") {
    try {
      chmodSync(dir, 0o700);
      chmodSync(sessionsDir, 0o700);
    } catch {
      // ignore permissions error in non-standard environments
    }
  }
  return dir;
}
