import { execFile } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { findExecutable, getNexusAdaptersDir } from "../agents-store.mjs";
import { getNativeConfig } from "../registry/registry.mjs";

export interface AcpAdapterInfo {
  required: boolean;
  package?: string;
  binary?: string;
}

export interface AcpAdapterStatus extends AcpAdapterInfo {
  installed: boolean;
  path?: string;
}

export interface InstallAcpAdapterOptions {
  adaptersDir?: string;
  packageManager?: string;
  timeoutMs?: number;
}

export function getAcpAdapterInfo(agentId: string): AcpAdapterInfo {
  const native = getNativeConfig(agentId);
  if (!native || !native.adapterPackage) {
    return { required: false };
  }
  return {
    required: true,
    package: native.adapterPackage,
    binary: native.adapterBinary || native.command || agentId,
  };
}

export function checkAcpAdapterStatus(agentId: string, customAdaptersDir?: string): AcpAdapterStatus {
  const info = getAcpAdapterInfo(agentId);
  if (!info.required) {
    return { required: false, installed: true };
  }

  const binary = info.binary!;
  const adaptersDir = customAdaptersDir ?? getNexusAdaptersDir();
  const directBinPath = path.join(
    adaptersDir,
    "node_modules",
    ".bin",
    process.platform === "win32" ? `${binary}.cmd` : binary,
  );

  if (existsSync(directBinPath)) {
    return {
      required: true,
      installed: true,
      package: info.package,
      binary,
      path: directBinPath,
    };
  }

  const execPath = findExecutable(binary);
  if (execPath) {
    return {
      required: true,
      installed: true,
      package: info.package,
      binary,
      path: execPath,
    };
  }

  return {
    required: true,
    installed: false,
    package: info.package,
    binary,
  };
}

export function detectPackageManager(override?: string): { pm: string; execPath: string } | null {
  const candidates = override ? [override] : ["npm", "bun", "pnpm"];
  for (const name of candidates) {
    const execPath = findExecutable(name);
    if (execPath) {
      return { pm: name, execPath };
    }
  }
  return null;
}

function ensureAdaptersPackageJson(adaptersDir: string): void {
  mkdirSync(adaptersDir, { recursive: true });
  const pkgJsonPath = path.join(adaptersDir, "package.json");
  if (!existsSync(pkgJsonPath)) {
    writeFileSync(
      pkgJsonPath,
      JSON.stringify(
        {
          name: "nexus-adapters",
          version: "1.0.0",
          private: true,
          description: "Isolated directory for ACP adapters managed by Nexus",
        },
        null,
        2,
      ) + "\n",
      "utf-8",
    );
  }
}

export async function installAcpAdapter(
  agentId: string,
  options: InstallAcpAdapterOptions = {},
): Promise<{ ok: boolean; path?: string; error?: string }> {
  const info = getAcpAdapterInfo(agentId);
  if (!info.required || !info.package) {
    return { ok: true };
  }

  const adaptersDir = options.adaptersDir ?? getNexusAdaptersDir();
  ensureAdaptersPackageJson(adaptersDir);

  const pm = detectPackageManager(options.packageManager);
  if (!pm) {
    return {
      ok: false,
      error: "No supported package manager found on host (checked npm, bun, pnpm).",
    };
  }

  const timeoutMs = options.timeoutMs ?? 120_000;
  let args: string[];
  if (pm.pm === "npm") {
    args = ["install", "--prefix", adaptersDir, info.package, "--save", "--no-audit", "--no-fund"];
  } else if (pm.pm === "bun") {
    args = ["add", "--cwd", adaptersDir, info.package];
  } else {
    args = ["add", "--dir", adaptersDir, info.package];
  }

  try {
    await new Promise<void>((resolve, reject) => {
      execFile(
        pm.execPath,
        args,
        {
          timeout: timeoutMs,
          windowsHide: true,
          shell: process.platform === "win32",
        },
        (error, stdout, stderr) => {
          if (error) {
            const detail = stderr?.trim() || stdout?.trim() || error.message;
            reject(new Error(`Failed to install ${info.package}: ${detail}`));
            return;
          }
          resolve();
        },
      );
    });

    const status = checkAcpAdapterStatus(agentId, adaptersDir);
    if (!status.installed) {
      return {
        ok: false,
        error: `Adapter package ${info.package} installed, but binary '${info.binary}' was not found.`,
      };
    }

    return { ok: true, path: status.path };
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

export async function uninstallAcpAdapter(
  agentId: string,
  options: InstallAcpAdapterOptions = {},
): Promise<{ ok: boolean; error?: string }> {
  const info = getAcpAdapterInfo(agentId);
  if (!info.required || !info.package) {
    return { ok: true };
  }

  const adaptersDir = options.adaptersDir ?? getNexusAdaptersDir();
  if (!existsSync(adaptersDir)) {
    return { ok: true };
  }

  const pm = detectPackageManager(options.packageManager);
  if (!pm) {
    return {
      ok: false,
      error: "No supported package manager found on host (checked npm, bun, pnpm).",
    };
  }

  const timeoutMs = options.timeoutMs ?? 60_000;
  let args: string[];
  if (pm.pm === "npm") {
    args = ["uninstall", "--prefix", adaptersDir, info.package];
  } else if (pm.pm === "bun") {
    args = ["remove", "--cwd", adaptersDir, info.package];
  } else {
    args = ["remove", "--dir", adaptersDir, info.package];
  }

  try {
    await new Promise<void>((resolve, reject) => {
      execFile(
        pm.execPath,
        args,
        {
          timeout: timeoutMs,
          windowsHide: true,
          shell: process.platform === "win32",
        },
        (error, stdout, stderr) => {
          if (error) {
            const detail = stderr?.trim() || stdout?.trim() || error.message;
            reject(new Error(`Failed to uninstall ${info.package}: ${detail}`));
            return;
          }
          resolve();
        },
      );
    });

    return { ok: true };
  } catch (err) {
    return {
      ok: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}
