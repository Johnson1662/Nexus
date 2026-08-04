import { homedir } from "node:os";
import path from "node:path";

export function resolveWorkspacePath(cwd?: string): string | undefined {
  if (!cwd || !cwd.trim()) return undefined;
  const expanded = cwd.trim().replace(/^~(?=$|[\\/])/, homedir());
  return path.resolve(expanded);
}
