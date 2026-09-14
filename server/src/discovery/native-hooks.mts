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

    try {
      renameSync(tmpPath, targetPath);
    } catch {
      writeFileSync(targetPath, sourceContent, { encoding: "utf8", mode: 0o644 });
      try { unlinkSync(tmpPath); } catch {}
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
