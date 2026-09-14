import path from "node:path";
import { homedir } from "node:os";
import { fileURLToPath } from "node:url";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  renameSync,
  unlinkSync,
  chmodSync,
} from "node:fs";

export interface NativeHookDefinition {
  agentId: string;
  name: string;
  description: string;
  targetDir: (home: string) => string;
  targetFileName: string;
  sourceAssetName: string;
  version: number;
  versionMarker: RegExp;
  isExecutable?: boolean;
  configHandler?: {
    getConfigPath: (home: string) => string;
    updateConfig: (existingContent: string | null, hookScriptPath: string) => string;
    removeConfig: (existingContent: string | null, hookScriptPath: string) => string | null;
    isConfigured: (content: string, hookScriptPath: string) => boolean;
  };
}

function createJsonHookConfigHandler(options: {
  getConfigPath: (home: string) => string;
  matcher: string;
}): NonNullable<NativeHookDefinition["configHandler"]> {
  function isNexusHook(hookObj: any, hookScriptPath: string): boolean {
    if (!hookObj || typeof hookObj !== "object") return false;
    if (hookObj.nexus === true) return true;
    if (typeof hookObj.command === "string") {
      const canonical = path.normalize(hookScriptPath);
      const cmd = path.normalize(hookObj.command);
      if (cmd.includes(canonical)) return true;
    }
    return false;
  }

  return {
    getConfigPath: options.getConfigPath,
    isConfigured: (content: string, hookScriptPath: string) => {
      try {
        const parsed = JSON.parse(content);
        const hooks = parsed?.hooks;
        if (!hooks || typeof hooks !== "object") return false;
        for (const event of ["SessionStart", "Stop", "SessionEnd"]) {
          const eventHooks = hooks[event];
          if (!Array.isArray(eventHooks)) return false;
          const hasNexus = eventHooks.some((group: any) =>
            Array.isArray(group?.hooks) &&
            group.hooks.some((h: any) => isNexusHook(h, hookScriptPath))
          );
          if (!hasNexus) return false;
        }
        return true;
      } catch {
        return false;
      }
    },
    updateConfig: (existingContent: string | null, hookScriptPath: string) => {
      let root: Record<string, any> = {};
      if (existingContent && existingContent.trim()) {
        try {
          root = JSON.parse(existingContent);
        } catch {
          throw new Error("HOOK_CONFIG_INVALID: 现有 Hook 配置文件包含非法 JSON，已中止操作以保护用户配置。");
        }
      }
      if (!root.hooks || typeof root.hooks !== "object" || Array.isArray(root.hooks)) {
        root.hooks = {};
      }

      for (const event of ["SessionStart", "Stop", "SessionEnd"] as const) {
        if (!Array.isArray(root.hooks[event])) {
          root.hooks[event] = [];
        }
        const action = event === "Stop" ? "stop" : (event === "SessionEnd" ? "exit" : "session");
        const command = `"${process.execPath}" "${hookScriptPath}" ${action}`;
        const nexusHookEntry = {
          type: "command",
          command,
          timeout: 30,
          nexus: true,
        };

        const existingGroup = root.hooks[event].find((g: any) =>
          Array.isArray(g?.hooks) &&
          g.hooks.some((h: any) => isNexusHook(h, hookScriptPath))
        );

        if (existingGroup) {
          const hookIdx = existingGroup.hooks.findIndex((h: any) => isNexusHook(h, hookScriptPath));
          if (hookIdx >= 0) {
            existingGroup.hooks[hookIdx] = nexusHookEntry;
          } else {
            existingGroup.hooks.push(nexusHookEntry);
          }
        } else {
          root.hooks[event].push({
            matcher: options.matcher,
            hooks: [nexusHookEntry],
          });
        }
      }

      return JSON.stringify(root, null, 2) + "\n";
    },
    removeConfig: (existingContent: string | null, hookScriptPath: string) => {
      if (!existingContent || !existingContent.trim()) return null;
      let root: Record<string, any> = {};
      try {
        root = JSON.parse(existingContent);
      } catch {
        throw new Error("HOOK_CONFIG_INVALID: 现有 Hook 配置文件包含非法 JSON，已中止操作以保护用户配置。");
      }

      if (!root.hooks || typeof root.hooks !== "object" || Array.isArray(root.hooks)) {
        return existingContent;
      }

      for (const event of ["SessionStart", "Stop", "SessionEnd"] as const) {
        if (!Array.isArray(root.hooks[event])) continue;
        root.hooks[event] = root.hooks[event]
          .map((g: any) => {
            if (!Array.isArray(g?.hooks)) return g;
            const remaining = g.hooks.filter((h: any) => !isNexusHook(h, hookScriptPath));
            return { ...g, hooks: remaining };
          })
          .filter((g: any) => Array.isArray(g.hooks) && g.hooks.length > 0);

        if (root.hooks[event].length === 0) {
          delete root.hooks[event];
        }
      }

      if (Object.keys(root.hooks).length === 0) {
        delete root.hooks;
      }

      if (Object.keys(root).length === 0) {
        return null;
      }

      return JSON.stringify(root, null, 2) + "\n";
    },
  };
}

const NATIVE_HOOK_REGISTRY: Record<string, NativeHookDefinition> = {
  omp: {
    agentId: "omp",
    name: "Nexus Ambient 监控扩展",
    description: "用于监听和控制终端中运行的 OMP 外部会话",
    targetDir: (home: string) => path.join(home, ".omp", "agent", "extensions"),
    targetFileName: "nexus-ambient.ts",
    sourceAssetName: "nexus-ambient-omp.ts",
    version: 1,
    versionMarker: /NEXUS_AMBIENT_INTEGRATION_VERSION=(\d+)/,
  },
  claude: {
    agentId: "claude",
    name: "Claude Code 终端监控 Hook",
    description: "用于监听和同步终端中运行的 Claude Code 命令行会话",
    targetDir: (home: string) => path.join(home, ".claude", "hooks"),
    targetFileName: "nexus-ambient.mjs",
    sourceAssetName: "nexus-ambient-claude.mjs",
    version: 2,
    versionMarker: /NEXUS_AMBIENT_INTEGRATION_VERSION=(\d+)/,
    isExecutable: true,
    configHandler: createJsonHookConfigHandler({
      getConfigPath: (home) => path.join(home, ".claude", "settings.json"),
      matcher: ".*",
    }),
  },
  codex: {
    agentId: "codex",
    name: "Codex 终端监控 Hook",
    description: "用于监听和同步终端中运行的 Codex CLI 命令行会话",
    targetDir: (home: string) => path.join(home, ".codex", "hooks"),
    targetFileName: "nexus-ambient.mjs",
    sourceAssetName: "nexus-ambient-codex.mjs",
    version: 2,
    versionMarker: /NEXUS_AMBIENT_INTEGRATION_VERSION=(\d+)/,
    isExecutable: true,
    configHandler: createJsonHookConfigHandler({
      getConfigPath: (home) => path.join(home, ".codex", "hooks.json"),
      matcher: "",
    }),
  },
};

export function getNativeHookDefinition(agentId: string): NativeHookDefinition | null {
  return NATIVE_HOOK_REGISTRY[agentId.toLowerCase()] ?? null;
}

export function getEffectiveHome(customHome?: string): string {
  return customHome || process.env.NEXUS_TEST_HOME || homedir();
}

function resolveSourceAssetPath(assetName: string): string | null {
  const currentDir = path.dirname(fileURLToPath(import.meta.url));
  const candidatePaths = [
    path.resolve(currentDir, "../integrations", assetName),
    path.resolve(currentDir, "../../assets/integrations", assetName),
    path.resolve(currentDir, "../assets/integrations", assetName),
    path.resolve(process.cwd(), "server/assets/integrations", assetName),
    path.resolve(process.cwd(), "server/dist/integrations", assetName),
  ];
  return candidatePaths.find((p) => existsSync(p)) ?? null;
}

function safeWriteFileAtomic(filePath: string, content: string): void {
  const dir = path.dirname(filePath);
  mkdirSync(dir, { recursive: true });
  const tmpPath = path.join(
    dir,
    `.${path.basename(filePath)}.${process.pid}.${Date.now()}.${Math.random().toString(36).slice(2, 8)}.tmp`,
  );
  writeFileSync(tmpPath, content, "utf8");
  renameSync(tmpPath, filePath);
}

const hookMutexes = new Map<string, Promise<void>>();

export async function withHookMutex<T>(key: string, fn: () => Promise<T>): Promise<T> {
  while (hookMutexes.has(key)) {
    try {
      await hookMutexes.get(key);
    } catch {}
  }
  let resolveCurrent!: () => void;
  const currentPromise = new Promise<void>((r) => (resolveCurrent = r));
  hookMutexes.set(key, currentPromise);
  try {
    return await fn();
  } finally {
    hookMutexes.delete(key);
    resolveCurrent();
  }
}

export interface NativeHookStatus {
  supported: boolean;
  installed: boolean;
  state: "not_installed" | "configured" | "active";
  path?: string;
  version?: number;
  description?: string;
}

export function checkNativeHookStatus(agentId: string, customHome?: string): NativeHookStatus {
  const def = getNativeHookDefinition(agentId);
  if (!def) {
    return { supported: false, installed: false, state: "not_installed" };
  }

  const home = getEffectiveHome(customHome);
  const targetDir = def.targetDir(home);
  const targetPath = path.join(targetDir, def.targetFileName);

  if (!existsSync(targetPath)) {
    return {
      supported: true,
      installed: false,
      state: "not_installed",
      path: targetPath,
      description: def.description,
    };
  }

  try {
    const content = readFileSync(targetPath, "utf8");
    const isManaged = content.includes("installed by nexus") || def.versionMarker.test(content);
    if (!isManaged) {
      // User's own file at this path without Nexus management marker — don't claim it
      return {
        supported: true,
        installed: false,
        state: "not_installed",
        path: targetPath,
        description: "存在未被 Nexus 接管的自定义扩展文件",
      };
    }

    const match = content.match(def.versionMarker);
    const version = match ? parseInt(match[1], 10) : def.version;

    if (def.configHandler) {
      const configPath = def.configHandler.getConfigPath(home);
      if (!existsSync(configPath)) {
        return {
          supported: true,
          installed: false,
          state: "not_installed",
          path: targetPath,
          description: def.description,
        };
      }
      try {
        const configContent = readFileSync(configPath, "utf8");
        if (!def.configHandler.isConfigured(configContent, targetPath)) {
          return {
            supported: true,
            installed: false,
            state: "not_installed",
            path: targetPath,
            description: def.description,
          };
        }
      } catch {
        return {
          supported: true,
          installed: false,
          state: "not_installed",
          path: targetPath,
          description: def.description,
        };
      }
    }

    // For Codex, hooks require explicit trust in Codex before becoming active
    const state: NativeHookStatus["state"] = agentId.toLowerCase() === "codex" ? "configured" : "active";
    const description = agentId.toLowerCase() === "codex"
      ? "Hook 已配置 (需要在 Codex 中信任后生效)"
      : def.description;

    return {
      supported: true,
      installed: true,
      state,
      version,
      path: targetPath,
      description,
    };
  } catch {
    return {
      supported: true,
      installed: false,
      state: "not_installed",
      path: targetPath,
      description: def.description,
    };
  }
}

export async function installNativeHook(
  agentId: string,
  customHome?: string,
): Promise<{ ok: boolean; path?: string; error?: string }> {
  return withHookMutex(agentId, async () => {
  const def = getNativeHookDefinition(agentId);
  if (!def) {
    return { ok: false, error: `Agent ${agentId} 不支持 Native Hook` };
  }

  const sourcePath = resolveSourceAssetPath(def.sourceAssetName);
  if (!sourcePath) {
    return { ok: false, error: `未找到 Hook 资源模板: ${def.sourceAssetName}` };
  }

  const home = getEffectiveHome(customHome);
  const targetDir = def.targetDir(home);
  const targetPath = path.join(targetDir, def.targetFileName);

  try {
    // Pre-validate config before any filesystem modification
    let updatedConfigContent: string | null = null;
    let configPath: string | null = null;
    if (def.configHandler) {
      configPath = def.configHandler.getConfigPath(home);
      const existingConfig = existsSync(configPath) ? readFileSync(configPath, "utf8") : null;
      updatedConfigContent = def.configHandler.updateConfig(existingConfig, targetPath);
    }

    const sourceContent = readFileSync(sourcePath, "utf8");

    if (existsSync(targetPath)) {
      const existing = readFileSync(targetPath, "utf8");
      const isManaged = existing.includes("installed by nexus") || def.versionMarker.test(existing);
      if (!isManaged) {
        return {
          ok: false,
          error: `目标位置已存在非 Nexus 管理的扩展文件: ${targetPath}，为防数据丢失已中止`,
        };
      }
    }

    mkdirSync(targetDir, { recursive: true });
    if (process.platform !== "win32") {
      try {
        chmodSync(targetDir, 0o755);
      } catch {}
    }

    const tmpPath = path.join(
      targetDir,
      `.${def.targetFileName}.${process.pid}.${Date.now()}.${Math.random().toString(36).slice(2, 8)}.tmp`,
    );
    writeFileSync(tmpPath, sourceContent, { encoding: "utf8", mode: 0o644 });

    const backupPath = path.join(
      targetDir,
      `.${def.targetFileName}.bak.${process.pid}.${Date.now()}.${Math.random().toString(36).slice(2, 8)}.tmp`,
    );
    let hasBackup = false;
    if (existsSync(targetPath)) {
      renameSync(targetPath, backupPath);
      hasBackup = true;
    }

    try {
      renameSync(tmpPath, targetPath);
    } catch (renameErr) {
      if (hasBackup) {
        try { renameSync(backupPath, targetPath); } catch {}
      }
      try { unlinkSync(tmpPath); } catch {}
      throw renameErr;
    }

    if (def.isExecutable && process.platform !== "win32") {
      try {
        chmodSync(targetPath, 0o755);
      } catch {}
    }

    if (def.configHandler && configPath && updatedConfigContent !== null) {
      try {
        safeWriteFileAtomic(configPath, updatedConfigContent);
      } catch (configErr) {
        try { unlinkSync(targetPath); } catch {}
        if (hasBackup) {
          try { renameSync(backupPath, targetPath); } catch {}
        }
        throw configErr;
      }
    }

    // Both script and config succeeded; safely delete backup
    if (hasBackup) {
      try { unlinkSync(backupPath); } catch {}
    }

    console.log(`[native-hooks] installed ${agentId} hook (v${def.version}) to ${targetPath}`);
    return { ok: true, path: targetPath };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[native-hooks] failed to install ${agentId} hook: ${message}`);
    return { ok: false, error: message };
  }
  });
}

export async function uninstallNativeHook(
  agentId: string,
  customHome?: string,
): Promise<{ ok: boolean; error?: string }> {
  return withHookMutex(agentId, async () => {
  const def = getNativeHookDefinition(agentId);
  if (!def) {
    return { ok: false, error: `Agent ${agentId} 不支持 Native Hook` };
  }

  const home = getEffectiveHome(customHome);
  const targetDir = def.targetDir(home);
  const targetPath = path.join(targetDir, def.targetFileName);

  if (!existsSync(targetPath)) {
    return { ok: true };
  }

  try {
    // Pre-validate config before any deletion
    let cleanedConfigContent: string | null = null;
    let configPath: string | null = null;
    if (def.configHandler) {
      configPath = def.configHandler.getConfigPath(home);
      if (existsSync(configPath)) {
        const existingConfig = readFileSync(configPath, "utf8");
        cleanedConfigContent = def.configHandler.removeConfig(existingConfig, targetPath);
      }
    }

    const content = readFileSync(targetPath, "utf8");
    const isManaged = content.includes("installed by nexus") || def.versionMarker.test(content);
    if (!isManaged) {
      return {
        ok: false,
        error: `目标文件非 Nexus 管理扩展，拒绝删除: ${targetPath}`,
      };
    }

    const backupPath = path.join(
      targetDir,
      `.${def.targetFileName}.bak.${process.pid}.${Date.now()}.${Math.random().toString(36).slice(2, 8)}.tmp`,
    );
    renameSync(targetPath, backupPath);

    try {
      if (def.configHandler && configPath && existsSync(configPath)) {
        if (cleanedConfigContent === null) {
          unlinkSync(configPath);
        } else {
          safeWriteFileAtomic(configPath, cleanedConfigContent);
        }
      }
      try { unlinkSync(backupPath); } catch {}
    } catch (configErr) {
      try { renameSync(backupPath, targetPath); } catch {}
      throw configErr;
    }

    console.log(`[native-hooks] uninstalled ${agentId} hook from ${targetPath}`);
    return { ok: true };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[native-hooks] failed to uninstall ${agentId} hook: ${message}`);
    return { ok: false, error: message };
  }
  });
}

export function listNativeHooks(customHome?: string): Array<{
  agentId: string;
  name: string;
  supported: boolean;
  installed: boolean;
  state: "not_installed" | "configured" | "active";
  path?: string;
  version?: number;
  description?: string;
}> {
  return Object.values(NATIVE_HOOK_REGISTRY).map((def) => {
    const status = checkNativeHookStatus(def.agentId, customHome);
    return {
      agentId: def.agentId,
      name: def.name,
      supported: status.supported,
      installed: status.installed,
      state: status.state,
      path: status.path,
      version: status.version,
      description: status.description,
    };
  });
}

/**
 * Called by daemon bootstrap: if a hook is ALREADY installed by Nexus,
 * keeps it updated to the newest version. Does NOT auto-install if missing.
 */
export function updateInstalledHooksIfPresent(customHome?: string): void {
  for (const def of Object.values(NATIVE_HOOK_REGISTRY)) {
    const status = checkNativeHookStatus(def.agentId, customHome);
    if (status.installed && (status.version ?? 0) < def.version) {
      installNativeHook(def.agentId, customHome).catch(() => {});
    }
  }
}
