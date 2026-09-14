import { execFile } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import path from "node:path";
import { findExecutable, getNexusAdaptersDir, findAgentExecutable, getInstalledAgents } from "../agents-store.mjs";
import { findExecutableDetailed } from "../agents-store.mjs";
import { getNativeConfig } from "../registry/registry.mjs";

export interface AcpAdapterInfo {
  required: boolean;
  package?: string;
  binary?: string;
}

export type AcpAdapterSource = "managed" | "external" | "none";

export interface AcpAdapterStatus extends AcpAdapterInfo {
  installed: boolean;
  source: AcpAdapterSource;
  nodeCompatible: boolean;
  path?: string;
}

export interface InstallAcpAdapterOptions {
  adaptersDir?: string;
  packageManager?: string;
  timeoutMs?: number;
}

const adapterMutexes = new Map<string, Promise<void>>();

export async function withAdapterMutex<T>(key: string, fn: () => Promise<T>): Promise<T> {
  while (adapterMutexes.has(key)) {
    try {
      await adapterMutexes.get(key);
    } catch {}
  }
  let resolveCurrent!: () => void;
  const currentPromise = new Promise<void>((r) => (resolveCurrent = r));
  adapterMutexes.set(key, currentPromise);
  try {
    return await fn();
  } finally {
    adapterMutexes.delete(key);
    resolveCurrent();
  }
}

export function checkNodeCompatibility(agentId?: string): { ok: boolean; version: string; minRequired: number } {
  const native = agentId ? getNativeConfig(agentId) : null;
  const minRequired = native?.minNodeMajor ?? 18;
  const major = parseInt(process.versions.node.split(".")[0], 10);
  return {
    ok: major >= minRequired,
    version: process.version,
    minRequired,
  };
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
    return { required: false, installed: true, source: "none", nodeCompatible: true };
  }

  const nodeCompat = checkNodeCompatibility(agentId).ok;
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
      source: "managed",
      nodeCompatible: nodeCompat,
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
      source: "external",
      nodeCompatible: nodeCompat,
      package: info.package,
      binary,
      path: execPath,
    };
  }

  return {
    required: true,
    installed: false,
    source: "none",
    nodeCompatible: nodeCompat,
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
  const adaptersDir = path.resolve(options.adaptersDir ?? getNexusAdaptersDir());
  return withAdapterMutex(adaptersDir, async () => {
  const info = getAcpAdapterInfo(agentId);
  if (!info.required || !info.package) {
    return { ok: true };
  }

  const nodeCheck = checkNodeCompatibility(agentId);
  if (!nodeCheck.ok) {
    return {
      ok: false,
      error: `当前 Node.js 版本 (${nodeCheck.version}) 低于 ${info.package} 所需的最低版本 (>= v${nodeCheck.minRequired}.0.0)，请先升级 Node.js`,
    };
  }

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
  });
}

export async function uninstallAcpAdapter(
  agentId: string,
  options: InstallAcpAdapterOptions = {},
): Promise<{ ok: boolean; error?: string }> {
  const adaptersDir = path.resolve(options.adaptersDir ?? getNexusAdaptersDir());
  return withAdapterMutex(adaptersDir, async () => {
  const info = getAcpAdapterInfo(agentId);
  if (!info.required || !info.package) {
    return { ok: true };
  }

  const directBinPath = path.join(
    adaptersDir,
    "node_modules",
    ".bin",
    process.platform === "win32" ? `${info.binary}.cmd` : info.binary!,
  );

  if (!existsSync(directBinPath)) {
    const execPath = findExecutable(info.binary!);
    if (execPath) {
      return {
        ok: false,
        error: `适配器 '${info.binary}' 位于系统全局目录 (${execPath})，非 Nexus 管理目录，请在终端手动卸载全局 npm 包`,
      };
    }
    return { ok: true };
  }

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
  });
}

export interface NativeAcpLaunch {
  cmd: string;
  args: string[];
  env: Record<string, string>;
  isAdapter: boolean;
  adapterPackage?: string;
}

export type NativeAcpLaunchResult =
  | { ok: true; launch: NativeAcpLaunch }
  | { ok: false; error: string; code: "NOT_ENABLED" | "ADAPTER_MISSING" | "CLI_MISSING" | "NODE_INCOMPATIBLE" };

export function resolveAdapterDirectJs(packageDir: string): string | null {
  try {
    const pkgJsonPath = path.join(packageDir, "package.json");
    if (!existsSync(pkgJsonPath)) return null;
    const raw = readFileSync(pkgJsonPath, "utf8");
    const parsed = JSON.parse(raw);
    const bin = parsed?.bin;
    if (typeof bin === "string") {
      const entry = path.resolve(packageDir, bin);
      return existsSync(entry) ? entry : null;
    }
    if (typeof bin === "object" && bin !== null) {
      const firstBin = Object.values(bin)[0];
      if (typeof firstBin === "string") {
        const entry = path.resolve(packageDir, firstBin);
        return existsSync(entry) ? entry : null;
      }
    }
    const main = parsed?.main;
    if (typeof main === "string") {
      const entry = path.resolve(packageDir, main);
      return existsSync(entry) ? entry : null;
    }
  } catch {}
  return null;
}

export function resolveNativeAcpLaunch(agentId: string): NativeAcpLaunchResult {
  const installedAgent = getInstalledAgents().find((a) => a.agentId === agentId);
  const customEnv = installedAgent?.customEnv || {};
  const customArgs = installedAgent?.customArgs;

  // Custom agents installed by user or tests with customCommand
  if (installedAgent?.source === "custom") {
    const cmd = installedAgent.customCommand;
    if (!cmd) {
      return {
        ok: false,
        error: `Custom agent '${agentId}' has no command specified`,
        code: "CLI_MISSING",
      };
    }
    const found = findExecutableDetailed(cmd);
    return {
      ok: true,
      launch: {
        cmd: found?.path ?? cmd,
        args: customArgs || [],
        env: customEnv,
        isAdapter: false,
      },
    };
  }

  const native = getNativeConfig(agentId);
  if (!native || !native.enabled) {
    return {
      ok: false,
      error: `Native ACP not enabled for agent '${agentId}'`,
      code: "NOT_ENABLED",
    };
  }

  const adapterStatus = checkAcpAdapterStatus(agentId);

  if (adapterStatus.required) {
    if (!adapterStatus.installed || !adapterStatus.path) {
      return {
        ok: false,
        error: `Agent '${agentId}' requires ACP adapter '${adapterStatus.package}', but it is not installed.`,
        code: "ADAPTER_MISSING",
      };
    }
    if (!adapterStatus.nodeCompatible) {
      const nodeCheck = checkNodeCompatibility(agentId);
      return {
        ok: false,
        error: `当前 Node.js 版本 (${nodeCheck.version}) 低于 ${adapterStatus.package} 所需的最低版本 (>= v${nodeCheck.minRequired}.0.0)`,
        code: "NODE_INCOMPATIBLE",
      };
    }

    if (native.requiresBaseCli) {
      const baseCli = findAgentExecutable(agentId);
      if (!baseCli) {
        return {
          ok: false,
          error: `Agent '${agentId}' requires base CLI to be installed on host`,
          code: "CLI_MISSING",
        };
      }
    }

    let cmd = adapterStatus.path;
    let args: string[] = customArgs ?? native.args ?? [];

    if (process.platform === "win32" && (cmd.endsWith(".cmd") || cmd.endsWith(".bat"))) {
      const adaptersDir = getNexusAdaptersDir();
      const pkgDir = path.join(adaptersDir, "node_modules", adapterStatus.package!);
      const directJs = resolveAdapterDirectJs(pkgDir);
      if (directJs) {
        cmd = process.execPath;
        args = [directJs, ...args];
      } else {
        cmd = process.env.ComSpec || "cmd.exe";
        args = ["/d", "/s", "/c", `"${adapterStatus.path}"`, ...args];
      }
    }

    return {
      ok: true,
      launch: {
        cmd,
        args,
        env: { ...(native.env || {}), ...customEnv },
        isAdapter: true,
        adapterPackage: adapterStatus.package,
      },
    };
  }

  // Non-adapter native agents (e.g. OMP, OpenCode, Cursor)
  const found = findAgentExecutable(agentId);
  if (!found) {
    return {
      ok: false,
      error: `Agent command for '${agentId}' not found in PATH or known locations`,
      code: "CLI_MISSING",
    };
  }

  return {
    ok: true,
    launch: {
      cmd: found.path,
      args: customArgs ?? native.args ?? [],
      env: { ...(native.env || {}), ...customEnv },
      isAdapter: false,
    },
  };
}
