import { randomBytes, timingSafeEqual } from "node:crypto";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const TOKEN_DIR = join(homedir(), ".nexus");
const TOKEN_FILE = join(TOKEN_DIR, "server.token");
const INSECURE_ENV = "NEXUS_ALLOW_INSECURE";

let cachedToken: string | undefined;
let insecureLogged = false;

function tokenFromEnvironment(): string | undefined {
  const token = process.env.NEXUS_AUTH_TOKEN?.trim();
  return token ? token : undefined;
}

function persistToken(token: string): void {
  mkdirSync(TOKEN_DIR, { recursive: true, mode: 0o700 });
  try {
    writeFileSync(TOKEN_FILE, token, { encoding: "utf8", mode: 0o600 });
  } catch {
    // Another bridge process may have created the token concurrently. Read it
    // below rather than replacing a token that an existing process is using.
  }
  try { chmodSync(TOKEN_FILE, 0o600); } catch { /* best effort on Windows */ }
}

/** Load the configured token, generating and persisting one on first use. */
export function getAuthToken(): string {
  if (cachedToken) return cachedToken;

  const configured = tokenFromEnvironment();
  if (configured) {
    cachedToken = configured;
    return configured;
  }

  mkdirSync(TOKEN_DIR, { recursive: true, mode: 0o700 });
  try {
    const existing = readFileSync(TOKEN_FILE, "utf8").trim();
    if (existing) {
      cachedToken = existing;
      try { chmodSync(TOKEN_FILE, 0o600); } catch { /* best effort on Windows */ }
      return existing;
    }
  } catch {
    // First run or an unreadable stale file: replace it with a new token.
  }

  const generated = randomBytes(32).toString("base64url");
  persistToken(generated);
  cachedToken = generated;
  return generated;
}

/**
 * Compare a presented bearer token without leaking length/content through the
 * comparison operation. Empty/malformed values are always unauthorized.
 */
export function timingSafeTokenEqual(presented: string | undefined, expected = getAuthToken()): boolean {
  if (!presented || !expected) return false;
  const actualBytes = Buffer.from(presented, "utf8");
  const expectedBytes = Buffer.from(expected, "utf8");
  if (actualBytes.length !== expectedBytes.length) return false;
  return timingSafeEqual(actualBytes, expectedBytes);
}

function insecureDevelopmentMode(): boolean {
  if (process.env[INSECURE_ENV] !== "1") return false;
  if (!insecureLogged) {
    insecureLogged = true;
    console.warn(`[auth] ${INSECURE_ENV}=1 enabled; bridge authentication is bypassed for local development`);
  }
  return true;
}

/** Validate the exact Authorization: Bearer <token> contract. */
export function isAuthorizedHeader(value: string | string[] | undefined): boolean {
  if (insecureDevelopmentMode()) return true;
  const header = Array.isArray(value) ? value[0] : value;
  if (!header) return false;
  const match = /^Bearer ([^\s]+)$/.exec(header.trim());
  return match ? timingSafeTokenEqual(match[1]) : false;
}

export function isInsecureDevelopmentMode(): boolean {
  return insecureDevelopmentMode();
}

export const AUTH_TOKEN_FILE = TOKEN_FILE;
