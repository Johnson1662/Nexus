import path from "node:path";
import { homedir } from "node:os";
import { getAgentLaunchArgs } from "./discovery/agents.mjs";

export interface ModelListModel {
  modelId: string;
  name: string;
}

export interface ModelListMode {
  value: string;
  name: string;
}

export interface ModelList {
  models: ModelListModel[];
  modes: ModelListMode[];
}

interface CacheEntry {
  value: ModelList;
  timestamp: number;
}

const CACHE_TTL_MS = 5 * 60 * 1000;
const ANYWHERE_DIR = path.join(homedir(), ".anywhere");
const modelCache = new Map<string, CacheEntry>();
const inflightQueries = new Map<string, Promise<ModelList>>();

function normalizeCwd(cwd?: string): string {
  const resolved = path.resolve(cwd && cwd.length > 0 ? cwd : ANYWHERE_DIR);
  return process.platform === "win32" ? resolved.toLowerCase() : resolved;
}

export function getModelCacheKey(agent: string, cwd?: string): string {
  const args = getAgentLaunchArgs(agent).join("\u0000");
  return `${agent}:${normalizeCwd(cwd)}:${args}`;
}

export function extractModelList(acpResult: unknown): ModelList {
  const result = acpResult as Record<string, any>;
  let models = Array.isArray(result?.models?.availableModels) ? result.models.availableModels : [];
  let modes = Array.isArray(result?.modes?.availableModes) ? result.modes.availableModes : [];

  const configOptions = Array.isArray(result?.configOptions) ? result.configOptions : [];
  if (models.length === 0) {
    models = extractFromConfigOptions(configOptions, "model");
  }
  if (modes.length === 0) {
    modes = extractFromConfigOptions(configOptions, "mode");
  }

  return {
    models: models
      .map((model: any): ModelListModel | null => {
        const modelId = model?.modelId ?? model?.value ?? model?.id;
        const name = model?.name ?? modelId;
        if (!modelId || !name) return null;
        return { modelId: String(modelId), name: String(name) };
      })
      .filter((model: ModelListModel | null): model is ModelListModel => model !== null),
    modes: modes
      .map((mode: any): ModelListMode | null => {
        const value = mode?.id ?? mode?.value;
        const name = mode?.name ?? value;
        if (!value || !name) return null;
        return { value: String(value), name: String(name) };
      })
      .filter((mode: ModelListMode | null): mode is ModelListMode => mode !== null),
  };
}

function extractFromConfigOptions(
  configOptions: any[],
  category: string,
): Array<{ value: string; name: string }> {
  const extracted: Array<{ value: string; name: string }> = [];
  for (const option of configOptions) {
    if (option?.category !== category || option?.type !== "select") continue;
    const options = option.options;
    if (!Array.isArray(options)) continue;
    for (const item of options) {
      if (item?.group !== undefined) {
        const groupOptions = item.options;
        if (!Array.isArray(groupOptions)) continue;
        for (const sub of groupOptions) {
          if (sub?.value && sub?.name) {
            extracted.push({ value: String(sub.value), name: String(sub.name) });
          }
        }
      } else if (item?.value && item?.name) {
        extracted.push({ value: String(item.value), name: String(item.name) });
      }
    }
  }
  return extracted;
}

export function getCachedModelList(agent: string, cwd?: string, allowStale: boolean = false): ModelList | null {
  const entry = modelCache.get(getModelCacheKey(agent, cwd));
  if (!entry) return null;
  if (allowStale || Date.now() - entry.timestamp < CACHE_TTL_MS) {
    return entry.value;
  }
  return null;
}

export function setCachedModelList(agent: string, cwd: string | undefined, value: ModelList): void {
  modelCache.set(getModelCacheKey(agent, cwd), { value, timestamp: Date.now() });
}

export function invalidateModelListCache(agent?: string): void {
  if (!agent) {
    modelCache.clear();
    inflightQueries.clear();
    return;
  }
  const prefix = `${agent}:`;
  for (const key of Array.from(modelCache.keys())) {
    if (key.startsWith(prefix)) modelCache.delete(key);
  }
  for (const key of Array.from(inflightQueries.keys())) {
    if (key.startsWith(prefix)) inflightQueries.delete(key);
  }
}

export async function queryModelListOnce(
  agent: string,
  cwd: string | undefined,
  refresh: boolean,
  query: () => Promise<ModelList>,
): Promise<ModelList> {
  const key = getModelCacheKey(agent, cwd);
  if (!refresh) {
    const cached = getCachedModelList(agent, cwd);
    if (cached) return cached;
    const inflight = inflightQueries.get(key);
    if (inflight) return await inflight;
  }

  const stale = getCachedModelList(agent, cwd, true);
  const promise = query()
    .then((value) => {
      modelCache.set(key, { value, timestamp: Date.now() });
      return value;
    })
    .catch((err: unknown) => {
      if (stale) return stale;
      throw err;
    })
    .finally(() => {
      if (inflightQueries.get(key) === promise) {
        inflightQueries.delete(key);
      }
    });

  inflightQueries.set(key, promise);
  return await promise;
}
