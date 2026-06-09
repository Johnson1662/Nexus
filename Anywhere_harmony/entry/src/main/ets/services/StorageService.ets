import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { WorkspaceStore, WorkspaceInfo, HostStore, DeviceEntry, HostInfo, ServerSession } from '../common/model/WorkspaceInfo';
import { ChatStore, ModelItem, ModeItem } from '../common/model/ChatState';

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
    try {
      await this.dataPreferences.put(key, value);
      await this.dataPreferences.flush();
    } catch (e) {}
  }

  async getString(key: string, def: string): Promise<string> {
    if (!this.dataPreferences) return def;
    try {
      return await this.dataPreferences.get(key, def) as string;
    } catch (e) {
      return def;
    }
  }

  async putStringArray(key: string, value: string[]): Promise<void> {
    if (!this.dataPreferences) return;
    try {
      await this.dataPreferences.put(key, JSON.stringify(value));
      await this.dataPreferences.flush();
    } catch (e) {}
  }

  async getStringArray(key: string, def: string[]): Promise<string[]> {
    if (!this.dataPreferences) return def;
    try {
      let raw = await this.dataPreferences.get(key, JSON.stringify(def)) as string;
      try {
        return JSON.parse(raw) as string[];
      } catch {
        return def;
      }
    } catch (e) {
      return def;
    }
  }

  async putObject(key: string, value: object): Promise<void> {
    if (!this.dataPreferences) return;
    try {
      await this.dataPreferences.put(key, JSON.stringify(value));
      await this.dataPreferences.flush();
    } catch (e) {}
  }

  async getObject<T>(key: string, def: T): Promise<T> {
    if (!this.dataPreferences) return def;
    try {
      let raw = await this.dataPreferences.get(key, JSON.stringify(def)) as string;
      try {
        return JSON.parse(raw) as T;
      } catch {
        return def;
      }
    } catch (e) {
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
  DEVICE_AGENTS_CACHE: string;
  HIERARCHY_CACHE: string;
  HOST_ID: string;
  SERVER_HOST_PUBLIC_KEY: string;
  HOST_ED25519_PUBLIC_KEY: string;
  APP_LANGUAGE: string;
  COLOR_MODE: string;
}

export const PrefsKeys: PrefsKeysType = {
  SERVER_URL: 'server_url',
  LAST_AGENT: 'last_agent',
  LAST_MODEL_ID: 'last_model_id',
  WORKSPACES: 'workspaces',
  WORKSPACE_INDEX: 'workspace_index',
  HOST_LIST: 'host_list',
  LAST_MESSAGE_ID: 'last_message_id',
  DEVICE_AGENTS_CACHE: 'device_agents_cache',
  HIERARCHY_CACHE: 'hierarchy_cache_v2',
  HOST_ID: 'host_id',
  SERVER_HOST_PUBLIC_KEY: 'server_host_public_key',
  HOST_ED25519_PUBLIC_KEY: 'host_ed25519_public_key',
  APP_LANGUAGE: 'app_language',
  COLOR_MODE: 'color_mode'
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

export const CACHE_SCHEMA_VERSION: number = 2;

export interface ModelProviderGroup {
  providerId: string;
  providerName: string;
  models: ModelItem[];
}

export interface AgentCacheData {
  schemaVersion: number;
  hostId: string;
  dayKey: string;
  fetchedAt: number;
  agents: import('../common/websocket/WSProtocol').AgentInfo[];
}

export interface ModelCacheData {
  schemaVersion: number;
  hostId: string;
  workspacePath: string;
  agentName: string;
  providers: ModelProviderGroup[];
  models: ModelItem[];
  modes: ModeItem[];
  dayKey: string;
  fetchedAt: number;
}

export interface SessionCacheData {
  schemaVersion: number;
  hostId: string;
  workspacePath: string;
  sessions: ServerSession[];
  fetchedAt: number;
}

export interface WorkspaceSelectionData {
  lastAgentByWorkspace: Record<string, string>;
  lastModelByAgent: Record<string, string>;
}

export interface HostWorkspaceCache {
  modelsByAgent: Record<string, ModelCacheData>;
  sessions: SessionCacheData | null;
  selection: WorkspaceSelectionData;
}

export interface HostCacheBucket {
  agents: AgentCacheData | null;
  workspaces: Record<string, HostWorkspaceCache>;
}

export interface HierarchyCacheData {
  schemaVersion: number;
  hosts: Record<string, HostCacheBucket>;
}

function sanitizeCacheSegment(value: string): string {
  if (value.length === 0) {
    return '__empty__';
  }
  return value.replace(/[^a-zA-Z0-9_\-:.\\/]/g, '_');
}

function getTodayKey(): string {
  let date: Date = new Date();
  let year: string = date.getFullYear().toString();
  let month: string = (date.getMonth() + 1).toString().padStart(2, '0');
  let day: string = date.getDate().toString().padStart(2, '0');
  return year + '-' + month + '-' + day;
}

function isDailyCacheExpired(dayKey: string): boolean {
  return dayKey.length === 0 || dayKey !== getTodayKey();
}

function getHierarchyDefault(): HierarchyCacheData {
  return {
    schemaVersion: CACHE_SCHEMA_VERSION,
    hosts: {}
  };
}

async function readHierarchyCache(): Promise<HierarchyCacheData> {
  let storage = StorageService.getInstance();
  let data: HierarchyCacheData = await storage.getObject<HierarchyCacheData>(PrefsKeys.HIERARCHY_CACHE, getHierarchyDefault());
  if (data.schemaVersion !== CACHE_SCHEMA_VERSION || data.hosts === undefined) {
    return getHierarchyDefault();
  }
  return data;
}

async function writeHierarchyCache(data: HierarchyCacheData): Promise<void> {
  data.schemaVersion = CACHE_SCHEMA_VERSION;
  await StorageService.getInstance().putObject(PrefsKeys.HIERARCHY_CACHE, data);
}

function ensureHostBucket(data: HierarchyCacheData, hostId: string): HostCacheBucket {
  let safeHostId: string = sanitizeCacheSegment(hostId);
  if (data.hosts[safeHostId] === undefined) {
    data.hosts[safeHostId] = {
      agents: null,
      workspaces: {}
    };
  }
  return data.hosts[safeHostId];
}

function ensureWorkspaceBucket(host: HostCacheBucket, workspacePath: string): HostWorkspaceCache {
  let key: string = sanitizeCacheSegment(workspacePath);
  if (host.workspaces[key] === undefined) {
    host.workspaces[key] = {
      modelsByAgent: {},
      sessions: null,
      selection: {
        lastAgentByWorkspace: {},
        lastModelByAgent: {}
      }
    };
  }
  return host.workspaces[key];
}

function inferProviderId(model: ModelItem): string {
  let source: string = model.modelId || model.name;
  let slashIndex: number = source.indexOf('/');
  if (slashIndex > 0) {
    return source.substring(0, slashIndex);
  }
  let colonIndex: number = source.indexOf(':');
  if (colonIndex > 0) {
    return source.substring(0, colonIndex);
  }
  let dashIndex: number = source.indexOf('-');
  if (dashIndex > 0) {
    return source.substring(0, dashIndex);
  }
  return 'default';
}

function buildProviderGroups(models: ModelItem[]): ModelProviderGroup[] {
  let grouped: Record<string, ModelItem[]> = {};
  for (let i: number = 0; i < models.length; i++) {
    let providerId: string = inferProviderId(models[i]);
    if (grouped[providerId] === undefined) {
      grouped[providerId] = [];
    }
    grouped[providerId].push(models[i]);
  }
  let keys: string[] = Object.keys(grouped);
  let result: ModelProviderGroup[] = [];
  for (let i: number = 0; i < keys.length; i++) {
    result.push({
      providerId: keys[i],
      providerName: keys[i],
      models: grouped[keys[i]]
    });
  }
  return result;
}

export async function saveAgentCache(hostId: string, agents: import('../common/websocket/WSProtocol').AgentInfo[]): Promise<void> {
  if (hostId.length === 0) return;
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  host.agents = {
    schemaVersion: CACHE_SCHEMA_VERSION,
    hostId: hostId,
    dayKey: getTodayKey(),
    fetchedAt: Date.now(),
    agents: agents
  };
  await writeHierarchyCache(data);
}

export async function loadAgentCache(hostId: string): Promise<AgentCacheData | null> {
  if (hostId.length === 0) return null;
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  if (host.agents === null || isDailyCacheExpired(host.agents.dayKey)) {
    return null;
  }
  return host.agents;
}

export async function saveWorkspaceModelCache(hostId: string, workspacePath: string, agentName: string,
  models: ModelItem[], modes: ModeItem[]): Promise<void> {
  if (hostId.length === 0 || workspacePath.length === 0 || agentName.length === 0) return;
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  let workspace: HostWorkspaceCache = ensureWorkspaceBucket(host, workspacePath);
  workspace.modelsByAgent[sanitizeCacheSegment(agentName)] = {
    schemaVersion: CACHE_SCHEMA_VERSION,
    hostId: hostId,
    workspacePath: workspacePath,
    agentName: agentName,
    providers: buildProviderGroups(models),
    models: models,
    modes: modes,
    dayKey: getTodayKey(),
    fetchedAt: Date.now()
  };
  await writeHierarchyCache(data);
}

export async function loadWorkspaceModelCache(hostId: string, workspacePath: string, agentName: string): Promise<ModelCacheData | null> {
  if (hostId.length === 0 || workspacePath.length === 0 || agentName.length === 0) return null;
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  let workspace: HostWorkspaceCache = ensureWorkspaceBucket(host, workspacePath);
  let cached: ModelCacheData | undefined = workspace.modelsByAgent[sanitizeCacheSegment(agentName)];
  if (cached === undefined || isDailyCacheExpired(cached.dayKey)) {
    return null;
  }
  return cached;
}

export async function saveWorkspaceSessionCache(hostId: string, workspacePath: string, sessions: ServerSession[]): Promise<void> {
  if (hostId.length === 0 || workspacePath.length === 0) return;
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  let workspace: HostWorkspaceCache = ensureWorkspaceBucket(host, workspacePath);
  workspace.sessions = {
    schemaVersion: CACHE_SCHEMA_VERSION,
    hostId: hostId,
    workspacePath: workspacePath,
    sessions: sessions,
    fetchedAt: Date.now()
  };
  await writeHierarchyCache(data);
}

export async function loadWorkspaceSessionCache(hostId: string, workspacePath: string): Promise<SessionCacheData | null> {
  if (hostId.length === 0 || workspacePath.length === 0) return null;
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  let workspace: HostWorkspaceCache = ensureWorkspaceBucket(host, workspacePath);
  return workspace.sessions;
}

export async function saveLastAgentSelection(hostId: string, workspacePath: string, agentName: string): Promise<void> {
  if (hostId.length === 0 || workspacePath.length === 0 || agentName.length === 0) return;
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  let workspace: HostWorkspaceCache = ensureWorkspaceBucket(host, workspacePath);
  workspace.selection.lastAgentByWorkspace[sanitizeCacheSegment(workspacePath)] = agentName;
  await writeHierarchyCache(data);
}

export async function loadLastAgentSelection(hostId: string, workspacePath: string): Promise<string> {
  if (hostId.length === 0 || workspacePath.length === 0) return '';
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  let workspace: HostWorkspaceCache = ensureWorkspaceBucket(host, workspacePath);
  let result: string | undefined = workspace.selection.lastAgentByWorkspace[sanitizeCacheSegment(workspacePath)];
  return result || '';
}

export async function saveLastModelSelection(hostId: string, workspacePath: string, agentName: string, modelId: string): Promise<void> {
  if (hostId.length === 0 || workspacePath.length === 0 || agentName.length === 0 || modelId.length === 0) return;
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  let workspace: HostWorkspaceCache = ensureWorkspaceBucket(host, workspacePath);
  workspace.selection.lastModelByAgent[sanitizeCacheSegment(agentName)] = modelId;
  await writeHierarchyCache(data);
}

export async function loadLastModelSelection(hostId: string, workspacePath: string, agentName: string): Promise<string> {
  if (hostId.length === 0 || workspacePath.length === 0 || agentName.length === 0) return '';
  let data: HierarchyCacheData = await readHierarchyCache();
  let host: HostCacheBucket = ensureHostBucket(data, hostId);
  let workspace: HostWorkspaceCache = ensureWorkspaceBucket(host, workspacePath);
  let result: string | undefined = workspace.selection.lastModelByAgent[sanitizeCacheSegment(agentName)];
  return result || '';
}

// Legacy wrappers retained for gradual migration.
export async function saveModelCache(agentName: string, models: ModelItem[], modes: ModeItem[]): Promise<void> {
  let hostId: string = ChatStore.currentDeviceId || AppStorage.get<string>('serverUrl') || '';
  let workspacePath: string = WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length
    ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path
    : '__global__';
  await saveWorkspaceModelCache(hostId, workspacePath, agentName, models, modes);
}

export async function loadModelCache(agentName: string): Promise<ModelCacheData | null> {
  let hostId: string = ChatStore.currentDeviceId || AppStorage.get<string>('serverUrl') || '';
  let workspacePath: string = WorkspaceStore.currentIndex >= 0 && WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length
    ? WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path
    : '__global__';
  return loadWorkspaceModelCache(hostId, workspacePath, agentName);
}

export async function saveSessionCache(agentName: string, cwd: string, sessions: ServerSession[]): Promise<void> {
  let hostId: string = ChatStore.currentDeviceId || AppStorage.get<string>('serverUrl') || '';
  await saveWorkspaceSessionCache(hostId, cwd, sessions);
}

export async function loadSessionCache(agentName: string, cwd: string): Promise<SessionCacheData | null> {
  let hostId: string = ChatStore.currentDeviceId || AppStorage.get<string>('serverUrl') || '';
  return loadWorkspaceSessionCache(hostId, cwd);
}
