import { execFile } from "node:child_process";
import { findExecutable } from "../agents-store.mjs";

export type HerdrCliErrorCode =
  | "HERDR_BIN_NOT_FOUND"
  | "HERDR_TIMEOUT"
  | "HERDR_EXIT"
  | "HERDR_BAD_JSON";

export class HerdrCliError extends Error {
  constructor(
    public readonly code: HerdrCliErrorCode,
    message: string,
    public readonly herdrCode?: string,
  ) {
    super(message);
    this.name = "HerdrCliError";
  }
}

const DEFAULT_TIMEOUT_MS = 5000;
const MAX_BUFFER_BYTES = 4 * 1024 * 1024;

/**
 * Absolute path to the Herdr executable, or null when it is not installed.
 * Resolution order: HERDR_BIN_PATH → PATH → known user binary directories.
 */
export function resolveHerdrBinary(): string | null {
  const override = process.env.HERDR_BIN_PATH?.trim();
  if (override) {
    // An explicit override is authoritative: when it does not resolve we report
    // "not installed" instead of silently falling back to PATH, so operators
    // (and the Herdr-less test simulation) get the state they asked for.
    return findExecutable(override);
  }
  return findExecutable("herdr");
}

function truncate(value: string, max = 200): string {
  const trimmed = value.trim();
  return trimmed.length > max ? `${trimmed.slice(0, max)}…` : trimmed;
}

/**
 * Herdr CLI transport.
 *
 * The CLI emits the same JSON envelope the socket API uses
 * (`{"id":"cli:<group>:<cmd>","result":{...}}`) for structured commands, and
 * human text for snapshot commands such as `agent read`. Both shapes are
 * therefore first-class: `run()` returns raw stdout, `runJson()` unwraps the
 * envelope.
 */
export class HerdrCliClient {
  static async run(args: string[], opts?: { timeoutMs?: number }): Promise<string> {
    const binary = resolveHerdrBinary();
    if (!binary) {
      throw new HerdrCliError("HERDR_BIN_NOT_FOUND", "Herdr executable not found");
    }

    const session = process.env.HERDR_SESSION?.trim();
    const argv = session ? ["--session", session, ...args] : [...args];
    const timeoutMs = opts?.timeoutMs ?? DEFAULT_TIMEOUT_MS;

    return new Promise<string>((resolve, reject) => {
      execFile(
        binary,
        argv,
        { timeout: timeoutMs, maxBuffer: MAX_BUFFER_BYTES, windowsHide: true, shell: false },
        (err, stdout, stderr) => {
          if (!err) {
            resolve(stdout);
            return;
          }
          const failure = err as NodeJS.ErrnoException & { killed?: boolean };
          if (failure.killed) {
            reject(new HerdrCliError("HERDR_TIMEOUT", `Herdr CLI timed out after ${timeoutMs}ms: herdr ${argv.join(" ")}`));
            return;
          }
          if (failure.code === "ENOENT") {
            reject(new HerdrCliError("HERDR_BIN_NOT_FOUND", `Herdr executable not found at ${binary}`));
            return;
          }
          // Herdr reports RPC failures as an error envelope on stdout *and* a
          // non-zero exit, so prefer that envelope: callers match on its code
          // (agent_not_found / pane_not_found) to tell "gone" from "broken".
          const envelope = parseErrorEnvelope(stdout);
          if (envelope) {
            reject(
              new HerdrCliError(
                "HERDR_EXIT",
                `Herdr CLI error [${envelope.code ?? "unknown"}]: ${envelope.message ?? ""}`.trim(),
                envelope.code,
              ),
            );
            return;
          }
          const detail = stderr?.trim() ? truncate(stderr) : truncate(stdout) || (err.message ?? "herdr failed");
          reject(new HerdrCliError("HERDR_EXIT", detail));
        },
      );
    });
  }

  static async runJson<T = unknown>(args: string[], opts?: { timeoutMs?: number }): Promise<T> {
    const stdout = await this.run(args, opts);
    const trimmed = stdout.trim();
    if (!trimmed.startsWith("{")) {
      throw new HerdrCliError(
        "HERDR_BAD_JSON",
        `Herdr CLI returned non-JSON output for "${args.join(" ")}": ${truncate(trimmed)}`,
      );
    }

    let parsed: { result?: T; error?: { code?: string; message?: string } };
    try {
      parsed = JSON.parse(trimmed);
    } catch (err) {
      throw new HerdrCliError(
        "HERDR_BAD_JSON",
        `Herdr CLI returned unparsable JSON for "${args.join(" ")}": ${truncate(trimmed)}`,
      );
    }

    if (parsed.error) {
      throw new HerdrCliError(
        "HERDR_EXIT",
        `Herdr CLI error [${parsed.error.code ?? "unknown"}]: ${parsed.error.message ?? ""}`.trim(),
        parsed.error.code,
      );
    }
    return parsed.result as T;
  }
}

function parseErrorEnvelope(stdout: string): { code?: string; message?: string } | null {
  const trimmed = stdout?.trim();
  if (!trimmed || !trimmed.startsWith("{")) return null;
  try {
    const parsed = JSON.parse(trimmed.split("\n")[0]) as { error?: { code?: string; message?: string } };
    return parsed?.error ?? null;
  } catch {
    return null;
  }
}
