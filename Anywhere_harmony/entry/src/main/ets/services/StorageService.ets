import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { WorkspaceStore, WorkspaceInfo, HostStore, DeviceEntry, HostInfo, ServerSession } from '../common/model/WorkspaceInfo';
import { ModelItem, ModeItem } from '../common/model/ChatState';

const PREF_NAME = 'app_settings';

export class StorageService {
  private static instance: StorageService;
  private dataPreferences: preferences.Preferences | null = null;
  private initPromise: Promise<void> | null = null;

  static getInstance(): StorageService {
    if (!StorageService.instance) {
      StorageService.instance = new StorageService();
    }
    return StorageService.instance;
  }

  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initPromise) return this.initPromise;
    this.initPromise = new Promise<void>((resolve, reject) => {
      preferences.getPreferences(context, PREF_NAME).then((pref) => {
        this.dataPreferences = pref;
        resolve();
      }).catch((err: Error) => {
        this.initPromise = null;
        reject(err);
      });
    });
    return this.initPromise;
  }

  async putString(key: string, value: string): Promise<void> {
    if (!this.dataPreferences) return;
    await this.dataPreferences.put(key, value);
    await this.dataPreferences.flush();
  }

  async getString(key: string, def: string): Promise<string> {
    if (!this.dataPreferences) return def;
    return await this.dataPreferences.get(key, def) as string;
  }

  async putStringArray(key: string, value: string[]): Promise<void> {
    if (!this.dataPreferences) return;
    await this.dataPreferences.put(key, JSON.stringify(value));
    await this.dataPreferences.flush();
  }

  async getStringArray(key: string, def: string[]): Promise<string[]> {
    if (!this.dataPreferences) return def;
    let raw = await this.dataPreferences.get(key, JSON.stringify(def)) as string;
    try {
      return JSON.parse(raw) as string[];
    } catch {
      return def;
    }
  }

  async putObject(key: string, value: object): Promise<void> {
    if (!this.dataPreferences) return;
    await this.dataPreferences.put(key, JSON.stringify(value));
    await this.dataPreferences.flush();
  }

  async getObject<T>(key: string, def: T): Promise<T> {
    if (!this.dataPreferences) return def;
    let raw = await this.dataPreferences.get(key, JSON.stringify(def)) as string;
    try {
      return JSON.parse(raw) as T;
    } catch {
      return def;
    }
  }
}

export interface PrefsKeysType {
  SERVER_URL: string;
  LAST_AGENT: string;
  LAST_MODEL_ID: string;
  WORKSPACES: string;
  WORKSPACE_INDEX: string;
  HOST_LIST: string;
  LAST_MESSAGE_ID: string;
}

export const PrefsKeys: PrefsKeysType = {
  SERVER_URL: 'server_url',
  LAST_AGENT: 'last_agent',
  LAST_MODEL_ID: 'last_model_id',
  WORKSPACES: 'workspaces',
  WORKSPACE_INDEX: 'workspace_index',
  HOST_LIST: 'host_list',
  LAST_MESSAGE_ID: 'last_message_id'
};

// Workspace data interface for serialization
export interface WorkspaceData {
  id: string;
  name: string;
  path: string;
}

function sanitizeScope(scope: string): string {
  return scope.replace(/[^a-zA-Z0-9]/g, '_');
}
// Configurable fallback scopes for workspace migration/hostId recovery.
// Populated by the app at startup with known hostname/IPs when needed.
let fallbackScopes: string[] = [];

export function configureFallbackScopes(scopes: string[]): void {
  fallbackScopes = scopes;
}

function getWorkspaceScopes(serverUrl: string): string[] {
  let scopes: string[] = [];
  for (let i: number = 0; i < HostStore.devices.length; i++) {
    let device: DeviceEntry = HostStore.devices[i];
    if (device.urls.indexOf(serverUrl) >= 0) {
      scopes.push('device_' + device.name);
      for (let j: number = 0; j < device.urls.length; j++) {
        scopes.push(device.urls[j]);
      }
      break;
    }
  }
  if (scopes.indexOf(serverUrl) < 0) {
    scopes.push(serverUrl);
  }
  
  // Append any configured fallback scopes (for hostId migration recovery)
  for (let i: number = 0; i < fallbackScopes.length; i++) {
    if (scopes.indexOf(fallbackScopes[i]) < 0) {
      scopes.push(fallbackScopes[i]);
    }
  }
  
  return scopes;
}

// Generate a scoped storage key for a workspace scope.
function scopeWorkspaceKey(base: string, scope: string): string {
  return base + '_' + sanitizeScope(scope);
}

// Save workspaces for the given server URL
export async function saveWorkspaces(serverUrl: string): Promise<void> {
  if (serverUrl.length === 0) return;
  let storage = StorageService.getInstance();
  let scopes: string[] = getWorkspaceScopes(serverUrl);
  let primaryScope: string = scopes[0];
  let data: WorkspaceData[] = [];
  for (let i = 0; i < WorkspaceStore.workspaces.length; i++) {
    let ws = WorkspaceStore.workspaces[i];
    data.push({ id: ws.id, name: ws.name, path: ws.path });
  }
  await storage.putObject(scopeWorkspaceKey(PrefsKeys.WORKSPACES, primaryScope), data);
  await storage.putString(scopeWorkspaceKey(PrefsKeys.WORKSPACE_INDEX, primaryScope), WorkspaceStore.currentIndex.toString());
}

// Load workspaces for the given server URL into WorkspaceStore
export async function loadWorkspaces(serverUrl: string): Promise<void> {
  if (serverUrl.length === 0) return;
  let storage = StorageService.getInstance();
  let scopes: string[] = getWorkspaceScopes(serverUrl);
  let data: WorkspaceData[] = [];
  let indexStr: string = '-1';
  let loadedScope: string = scopes[0];
  for (let i: number = 0; i < scopes.length; i++) {
    let scopedData: WorkspaceData[] = await storage.getObject<WorkspaceData[]>(
      scopeWorkspaceKey(PrefsKeys.WORKSPACES, scopes[i]), []);
    if (scopedData.length > 0) {
      data = scopedData;
      indexStr = await storage.getString(
        scopeWorkspaceKey(PrefsKeys.WORKSPACE_INDEX, scopes[i]), '-1');
      loadedScope = scopes[i];
      break;
    }
  }
  let workspaces: WorkspaceInfo[] = [];
  for (let i = 0; i < data.length; i++) {
    let d = data[i];
    let ws = new WorkspaceInfo();
    ws.id = d.id;
    ws.name = d.name;
    ws.path = d.path;
    workspaces.push(ws);
  }
  WorkspaceStore.workspaces = workspaces;
  WorkspaceStore.currentIndex = parseInt(indexStr, 10) || -1;
  if (data.length > 0 && loadedScope !== scopes[0]) {
    await saveWorkspaces(serverUrl);
  }
}

// Save device list
export async function saveHosts(): Promise<void> {
  let storage = StorageService.getInstance();
  let data: DeviceEntry[] = HostStore.devices;
  await storage.putObject(PrefsKeys.HOST_LIST, data);
}

function isOldHostList(data: object[]): boolean {
  if (data.length === 0) return false;
  let first: Record<string, Object> = data[0] as Record<string, Object>;
  return first['url'] !== undefined;
}

// Load device list (with migration from old HostInfo[] format)
export async function loadHosts(): Promise<void> {
  let storage = StorageService.getInstance();
  let raw: object[] = await storage.getObject<object[]>(PrefsKeys.HOST_LIST, []);
  if (isOldHostList(raw)) {
    let oldData: HostInfo[] = raw as HostInfo[];
    let devices: DeviceEntry[] = [];
    for (let i: number = 0; i < oldData.length; i++) {
      devices.push({ name: oldData[i].label, urls: [oldData[i].url] });
    }
    HostStore.devices = devices;
    await saveHosts();
  } else {
    HostStore.devices = raw as DeviceEntry[];
  }

  // Populate fallback scopes from saved devices for workspace recovery
  let scopes: string[] = [];
  for (let i: number = 0; i < HostStore.devices.length; i++) {
    let d: DeviceEntry = HostStore.devices[i];
    scopes.push('device_' + d.name);
    for (let j: number = 0; j < d.urls.length; j++) {
      if (scopes.indexOf(d.urls[j]) < 0) {
        scopes.push(d.urls[j]);
      }
    }
  }
  configureFallbackScopes(scopes);
}

// ── Persistent Cache (Models, Modes, Sessions) ──

/** 当前缓存 schema 版本，升级时递增以触发旧缓存失效 */
export const CACHE_SCHEMA_VERSION: number = 1;

/** 缓存 TTL：5 分钟 */
const CACHE_TTL_MS: number = 5 * 60 * 1000;

export function isCacheExpired(timestamp: number): boolean {
  return (Date.now() - timestamp) > CACHE_TTL_MS;
}

export interface ModelCacheData {
  schemaVersion: number;
  models: ModelItem[];
  modes: ModeItem[];
  timestamp: number;
}

export interface SessionCacheData {
  schemaVersion: number;
  sessions: ServerSession[];
  timestamp: number;
}

function cacheKey(prefix: string, agentName: string): string {
  let sanitized: string = agentName.replace(/[^a-zA-Z0-9_\-]/g, '_');
  return prefix + sanitized;
}

const CACHE_MODEL_PREFIX = 'cm_';
const CACHE_SESSION_PREFIX = 'cs_';

export async function saveModelCache(agentName: string, models: ModelItem[], modes: ModeItem[]): Promise<void> {
  if (agentName.length === 0) return;
  let storage = StorageService.getInstance();
  let key = cacheKey(CACHE_MODEL_PREFIX, agentName);
  let data: ModelCacheData = {
    schemaVersion: CACHE_SCHEMA_VERSION,
    models: models,
    modes: modes,
    timestamp: Date.now()
  };
  await storage.putString(key, JSON.stringify(data));
}

export async function loadModelCache(agentName: string): Promise<ModelCacheData | null> {
  if (agentName.length === 0) return null;
  let storage = StorageService.getInstance();
  let key = cacheKey(CACHE_MODEL_PREFIX, agentName);
  let raw = await storage.getString(key, '');
  if (raw.length === 0) return null;
  try {
    let data = JSON.parse(raw) as ModelCacheData;
    if (data.schemaVersion !== CACHE_SCHEMA_VERSION) return null;
    if (isCacheExpired(data.timestamp)) return null;
    return data;
  } catch {
    return null;
  }
}

export async function saveSessionCache(agentName: string, cwd: string, sessions: ServerSession[]): Promise<void> {
  if (agentName.length === 0 || cwd.length === 0) return;
  let storage = StorageService.getInstance();
  let key = cacheKey(CACHE_SESSION_PREFIX, agentName + '_' + cwd);
  let data: SessionCacheData = {
    schemaVersion: CACHE_SCHEMA_VERSION,
    sessions: sessions,
    timestamp: Date.now()
  };
  await storage.putString(key, JSON.stringify(data));
}

export async function loadSessionCache(agentName: string, cwd: string): Promise<SessionCacheData | null> {
  if (agentName.length === 0 || cwd.length === 0) return null;
  let storage = StorageService.getInstance();
  let key = cacheKey(CACHE_SESSION_PREFIX, agentName + '_' + cwd);
  let raw = await storage.getString(key, '');
  if (raw.length === 0) return null;
  try {
    let data = JSON.parse(raw) as SessionCacheData;
    if (data.schemaVersion !== CACHE_SCHEMA_VERSION) return null;
    if (isCacheExpired(data.timestamp)) return null;
    return data;
  } catch {
    return null;
  }
}
