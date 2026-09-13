import { homedir } from "node:os";
import path from "node:path";
import { mkdirSync, chmodSync, existsSync, realpathSync, statSync } from "node:fs";

/**
 * Canonical form of a workspace path: absolute, forward-slashed, no trailing
 * separator (except root), drive letter upper-cased on Windows.
 */
export function canonicalizeWorkspacePath(
  targetPath: string,
  platform: string = process.platform,
): string {
  if (!targetPath || !targetPath.trim()) return "";
  const expanded = targetPath.trim().replace(/^~(?=$|[\\/])/, homedir());
  const impl = platform === "win32" ? path.win32 : path.posix;
  let resolved = impl.resolve(expanded).replace(/\\/g, "/");
  if (platform === "win32" && /^[a-zA-Z]:/.test(resolved)) {
    resolved = resolved[0].toUpperCase() + resolved.slice(1);
  }
  if (resolved.length > 1 && resolved.endsWith("/")) {
    resolved = resolved.slice(0, -1);
  }
  return resolved;
}

/**
 * Compare two workspace paths under the target platform's case rules.
 * Windows is case-insensitive; POSIX (including macOS) stays case-sensitive.
 */
export function areWorkspacePathsEqual(
  a: string,
  b: string,
  platform: string = process.platform,
): boolean {
  const normA = canonicalizeWorkspacePath(a, platform);
  const normB = canonicalizeWorkspacePath(b, platform);
  if (platform === "win32") {
    return normA.toLowerCase() === normB.toLowerCase();
  }
  return normA === normB;
}

export function resolveWorkspacePath(cwd?: string): string | undefined {
  if (!cwd || !cwd.trim()) return undefined;
  const expanded = cwd.trim().replace(/^~(?=$|[\\/])/, homedir());
  return path.resolve(expanded);
}

/**
 * True when `candidate` is `parent` itself or lives inside it, using the target
 * platform's separator and case rules. Hand-rolled comparisons missed Windows
 * case folding and mixed separators, so sessions in the wrong directory could
 * pass a filter (or a correct one could be dropped).
 */
export function isWorkspacePathWithin(
  parent: string,
  candidate: string,
  platform: string = process.platform,
): boolean {
  const normalizedParent = canonicalizeWorkspacePath(parent, platform);
  const normalizedCandidate = canonicalizeWorkspacePath(candidate, platform);
  if (!normalizedParent || !normalizedCandidate) return false;
  const fold = (value: string) => (platform === "win32" ? value.toLowerCase() : value);
  const root = fold(normalizedParent);
  const target = fold(normalizedCandidate);
  if (root === target) return true;
  return target.startsWith(root.endsWith("/") ? root : `${root}/`);
}

export type WorkspaceErrorCode = "INVALID_WORKSPACE";

export class WorkspaceError extends Error {
  constructor(public readonly code: WorkspaceErrorCode, message: string) {
    super(message);
    this.name = "WorkspaceError";
  }
}

/**
 * Resolve a caller-supplied workspace directory.
 *
 * A missing cwd is a legitimate "use the default", but an explicitly supplied
 * cwd that does not exist is an error: silently running the agent in a different
 * directory makes it operate on the wrong files. Fail closed instead.
 */
export function resolveExplicitCwd(cwd: string | undefined, defaultDir: string): string {
  const requested = resolveWorkspacePath(cwd);
  if (!requested) {
    mkdirSync(defaultDir, { recursive: true });
    return defaultDir;
  }
  let stat;
  try {
    stat = statSync(requested);
  } catch {
    throw new WorkspaceError("INVALID_WORKSPACE", `workspace does not exist: ${requested}`);
  }
  if (!stat.isDirectory()) {
    throw new WorkspaceError("INVALID_WORKSPACE", `workspace is not a directory: ${requested}`);
  }
  return realpathSync(requested);
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
