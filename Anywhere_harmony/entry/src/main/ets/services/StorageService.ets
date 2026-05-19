import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

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
    this.initPromise = new Promise<void>((resolve) => {
      preferences.getPreferences(context, PREF_NAME).then((pref) => {
        this.dataPreferences = pref;
        resolve();
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
}

export const PrefsKeys: PrefsKeysType = {
  SERVER_URL: 'server_url',
  LAST_AGENT: 'last_agent',
  LAST_MODEL_ID: 'last_model_id',
  WORKSPACES: 'workspaces',
  WORKSPACE_INDEX: 'workspace_index'
};
