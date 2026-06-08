export class WorkspaceInfo {
  id: string = '';
  name: string = '';
  path: string = '';
}

export class ServerSession {
  /** ACP Session ID — AI Agent 的真实会话 ID，用于 load/resume，非 bridge session */
  sessionId: string = '';
  title: string = '';
  /** 最后活跃时间 (epoch ms) — server 返回 updatedAt (ISO) 或客户端接收时补 */
  createdAt: number = 0;
  currentModel?: string;
  model?: string;
  cwd?: string;
  agent?: string;
}

@ObservedV2
export class WorkspaceStoreModel {
  @Trace workspaces: WorkspaceInfo[] = [];
  @Trace currentIndex: number = -1;
}

export const WorkspaceStore: WorkspaceStoreModel = new WorkspaceStoreModel();

export interface DeviceEntry {
  name: string;
  urls: string[];
  hostId?: string;
  relayPin?: string;
}

// Legacy HostInfo — kept for migration only
export interface HostInfo {
  url: string;
  label: string;
}

@ObservedV2
export class HostStoreModel {
  @Trace devices: DeviceEntry[] = [];

  addOrUpdateDevice(device: DeviceEntry): void {
    let existing: number = -1;
    for (let i: number = 0; i < this.devices.length; i++) {
      let current = this.devices[i];
      if (device.hostId && current.hostId === device.hostId) {
        existing = i;
        break;
      }
      if (device.hostId && (!current.hostId || current.hostId.length === 0) && current.name === device.name) {
        existing = i;
        break;
      }
      if (!device.hostId && current.name === device.name) {
        existing = i;
        break;
      }
    }
    if (existing >= 0) {
      let current = this.devices[existing];
      if (device.hostId && (!current.hostId || current.hostId.length === 0)) {
        current.hostId = device.hostId;
      }
      if (device.relayPin && device.relayPin.length > 0) {
        current.relayPin = device.relayPin;
      }
      let existingUrls: string[] = current.urls;
      for (let i: number = 0; i < device.urls.length; i++) {
        let url: string = device.urls[i];
        if (existingUrls.indexOf(url) < 0) {
          existingUrls.push(url);
        }
      }
    } else {
      this.devices.push(device);
    }
    this.devices = [...this.devices];
  }

  removeDevice(index: number): void {
    this.devices.splice(index, 1);
    this.devices = [...this.devices];
  }

  getDeviceIndexByName(name: string): number {
    for (let i: number = 0; i < this.devices.length; i++) {
      if (this.devices[i].name === name) return i;
    }
    return -1;
  }
}

export const HostStore: HostStoreModel = new HostStoreModel();
