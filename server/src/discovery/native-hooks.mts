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
  return {
    getConfigPath: options.getConfigPath,
    isConfigured: (content: string, hookScriptPath: string) => {
      try {
        const parsed = JSON.parse(content);
        const hooks = parsed?.hooks;
        if (!hooks || typeof hooks !== "object") return false;
        const sessionHooks = hooks.SessionStart;
        if (!Array.isArray(sessionHooks)) return false;
        return sessionHooks.some((group: any) =>
          Array.isArray(group?.hooks) &&
          group.hooks.some((h: any) => typeof h?.command === "string" && h.command.includes("nexus-ambient"))
        );
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
          root = {};
        }
      }
      if (!root.hooks || typeof root.hooks !== "object" || Array.isArray(root.hooks)) {
        root.hooks = {};
      }

      for (const event of ["SessionStart", "Stop"] as const) {
        if (!Array.isArray(root.hooks[event])) {
          root.hooks[event] = [];
        }
        const action = event === "Stop" ? "stop" : "session";
        const command = `${hookScriptPath} ${action}`;
        const existingGroup = root.hooks[event].find((g: any) =>
          Array.isArray(g?.hooks) &&
          g.hooks.some((h: any) => typeof h?.command === "string" && h.command.includes("nexus-ambient"))
        );

        if (existingGroup) {
          existingGroup.hooks = [
            {
              type: "command",
              command,
              timeout: 30,
            },
          ];
          existingGroup.matcher = options.matcher;
        } else {
          root.hooks[event].push({
            matcher: options.matcher,
            hooks: [
              {
                type: "command",
                command,
                timeout: 30,
              },
            ],
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
        return null;
      }

      if (!root.hooks || typeof root.hooks !== "object" || Array.isArray(root.hooks)) {
        return existingContent;
      }

      for (const event of ["SessionStart", "Stop"] as const) {
        if (!Array.isArray(root.hooks[event])) continue;
        root.hooks[event] = root.hooks[event]
          .map((g: any) => {
            if (!Array.isArray(g?.hooks)) return g;
            const remaining = g.hooks.filter(
              (h: any) => !(typeof h?.command === "string" && h.command.includes("nexus-ambient"))
            );
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
    targetFileName: "nexus-ambient.sh",
    sourceAssetName: "nexus-ambient-claude.sh",
    version: 1,
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
    targetFileName: "nexus-ambient.sh",
    sourceAssetName: "nexus-ambient-codex.sh",
    version: 1,
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

export interface NativeHookStatus {
  supported: boolean;
  installed: boolean;
  path?: string;
  version?: number;
  description?: string;
}

export function checkNativeHookStatus(agentId: string, customHome?: string): NativeHookStatus {
  const def = getNativeHookDefinition(agentId);
  if (!def) {
    return { supported: false, installed: false };
  }

  const home = getEffectiveHome(customHome);
  const targetDir = def.targetDir(home);
  const targetPath = path.join(targetDir, def.targetFileName);

  if (!existsSync(targetPath)) {
    return {
      supported: true,
      installed: false,
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
            path: targetPath,
            description: def.description,
          };
        }
      } catch {
        return {
          supported: true,
          installed: false,
          path: targetPath,
          description: def.description,
        };
      }
    }

    return {
      supported: true,
      installed: true,
      version,
      path: targetPath,
      description: def.description,
    };
  } catch {
    return {
      supported: true,
      installed: false,
      path: targetPath,
      description: def.description,
    };
  }
}

export async function installNativeHook(
  agentId: string,
  customHome?: string,
): Promise<{ ok: boolean; path?: string; error?: string }> {
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
      if (hasBackup) {
        try { unlinkSync(backupPath); } catch {}
      }
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

    if (def.configHandler) {
      const configPath = def.configHandler.getConfigPath(home);
      const configDir = path.dirname(configPath);
      mkdirSync(configDir, { recursive: true });
      const existingConfig = existsSync(configPath) ? readFileSync(configPath, "utf8") : null;
      const updatedConfig = def.configHandler.updateConfig(existingConfig, targetPath);
      writeFileSync(configPath, updatedConfig, "utf8");
    }

    console.log(`[native-hooks] installed ${agentId} hook (v${def.version}) to ${targetPath}`);
    return { ok: true, path: targetPath };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[native-hooks] failed to install ${agentId} hook: ${message}`);
    return { ok: false, error: message };
  }
}

export async function uninstallNativeHook(
  agentId: string,
  customHome?: string,
): Promise<{ ok: boolean; error?: string }> {
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
    const content = readFileSync(targetPath, "utf8");
    const isManaged = content.includes("installed by nexus") || def.versionMarker.test(content);
    if (!isManaged) {
      return {
        ok: false,
        error: `目标文件非 Nexus 管理扩展，拒绝删除: ${targetPath}`,
      };
    }

    unlinkSync(targetPath);
    if (def.configHandler) {
      const configPath = def.configHandler.getConfigPath(home);
      if (existsSync(configPath)) {
        try {
          const existingConfig = readFileSync(configPath, "utf8");
          const cleaned = def.configHandler.removeConfig(existingConfig, targetPath);
          if (cleaned === null) {
            unlinkSync(configPath);
          } else {
            writeFileSync(configPath, cleaned, "utf8");
          }
        } catch {}
      }
    }
    console.log(`[native-hooks] uninstalled ${agentId} hook from ${targetPath}`);
    return { ok: true };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[native-hooks] failed to uninstall ${agentId} hook: ${message}`);
    return { ok: false, error: message };
  }
}

export function listNativeHooks(customHome?: string): Array<{
  agentId: string;
  name: string;
  supported: boolean;
  installed: boolean;
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
