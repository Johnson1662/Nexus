import { existsSync, statSync, unlinkSync, renameSync } from "node:fs";

export const DEFAULT_MAX_LOG_BYTES = 5 * 1024 * 1024; // 5MB

export function sanitizeLogText(text: string, secrets: string[] = []): string {
  let out = text
    .replace(/Bearer\s+[A-Za-z0-9_\-\.]{8,}/gi, "Bearer [REDACTED]")
    .replace(/([?&]token=)[A-Za-z0-9_\-\.]+/gi, "$1[REDACTED]")
    .replace(/\b(sk-[A-Za-z0-9_-]{16,})\b/g, "sk-[REDACTED]")
    .replace(/(password|secret|auth_token)["']?\s*[:=]\s*["']?[A-Za-z0-9_\-\.]{8,}["']?/gi, "$1=[REDACTED]");

  for (const secret of secrets) {
    if (secret && secret.length >= 8) {
      out = out.split(secret).join("[REDACTED]");
    }
  }
  return out;
}

export function rotateLogFile(logPath: string, maxBytes = DEFAULT_MAX_LOG_BYTES): boolean {
  try {
    if (!existsSync(logPath)) return false;
    const stat = statSync(logPath);
    if (stat.size <= maxBytes) return false;

    const backup = `${logPath}.1`;
    try { unlinkSync(backup); } catch {}
    renameSync(logPath, backup);
    return true;
  } catch {
    return false;
  }
}

export function installLogSanitizer(secrets: string[] = []): () => void {
  const origStdoutWrite = process.stdout.write.bind(process.stdout);
  const origStderrWrite = process.stderr.write.bind(process.stderr);

  process.stdout.write = function (chunk: any, ...args: any[]): boolean {
    if (typeof chunk === "string") {
      return origStdoutWrite(sanitizeLogText(chunk, secrets), ...args);
    } else if (Buffer.isBuffer(chunk)) {
      return origStdoutWrite(Buffer.from(sanitizeLogText(chunk.toString("utf8"), secrets)), ...args);
    }
    return origStdoutWrite(chunk, ...args);
  } as any;

  process.stderr.write = function (chunk: any, ...args: any[]): boolean {
    if (typeof chunk === "string") {
      return origStderrWrite(sanitizeLogText(chunk, secrets), ...args);
    } else if (Buffer.isBuffer(chunk)) {
      return origStderrWrite(Buffer.from(sanitizeLogText(chunk.toString("utf8"), secrets)), ...args);
    }
    return origStderrWrite(chunk, ...args);
  } as any;

  return () => {
    process.stdout.write = origStdoutWrite as any;
    process.stderr.write = origStderrWrite as any;
  };
}
