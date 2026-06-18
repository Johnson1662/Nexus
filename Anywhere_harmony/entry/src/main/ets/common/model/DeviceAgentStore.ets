import { AgentInfo } from '../websocket/WSProtocol';
import { StorageService, PrefsKeys } from '../../services/StorageService';

/** 每个已保存设备上发现的 ACP Agent 列表，按 hostId/hostname 索引 */
class DeviceAgentStoreModel {
  private cache: Map<string, AgentInfo[]> = new Map<string, AgentInfo[]>();
  private loaded: boolean = false;

  /** 获取某个设备上的 Agent 列表（从缓存，非异步） */
  getAgents(hostId: string): AgentInfo[] {
    if (hostId && hostId.length > 0 && this.cache.has(hostId)) {
      let result = this.cache.get(hostId);
      if (result) return result;
    }
    return [];
  }

  /** 保存某个设备的 Agent 列表到内存 + 持久化 */
  saveAgents(hostId: string, agents: AgentInfo[]): void {
    if (!hostId || hostId.length === 0) return;
    this.cache.set(hostId, agents);
    this.persist();
  }

  /** 异步加载持久化数据 */
  async loadFromDisk(): Promise<void> {
    if (this.loaded) return;
    let storage = StorageService.getInstance();
    try {
      let raw = await storage.getString(PrefsKeys.DEVICE_AGENTS_CACHE, '');
      if (raw && raw.length > 0) {
        let parsed: Record<string, AgentInfo[]> = JSON.parse(raw);
        let keys = Object.keys(parsed);
        for (let i = 0; i < keys.length; i++) {
          this.cache.set(keys[i], parsed[keys[i]]);
        }
      }
    } catch (e) {
      // 首次使用，缓存为空
    }
    this.loaded = true;
  }

  private async persist(): Promise<void> {
    let obj: Record<string, AgentInfo[]> = {};
    let entries = Array.from(this.cache.entries());
    for (let i = 0; i < entries.length; i++) {
      obj[entries[i][0]] = entries[i][1];
    }
    try {
      await StorageService.getInstance().putString(PrefsKeys.DEVICE_AGENTS_CACHE, JSON.stringify(obj));
    } catch (e) {}
  }
}

export const DeviceAgentStore: DeviceAgentStoreModel = new DeviceAgentStoreModel();
