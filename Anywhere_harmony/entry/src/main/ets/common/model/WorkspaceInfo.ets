export class WorkspaceInfo {
  id: string = '';
  name: string = '';
  path: string = '';
}

export class ServerSession {
  sessionId: string = '';
  title: string = '';
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
      if (this.devices[i].name === device.name) {
        existing = i;
        break;
      }
    }
    if (existing >= 0) {
      let existingUrls: string[] = this.devices[existing].urls;
      for (let i: number = 0; i < device.urls.length; i++) {
        let url: string = device.urls[i];
        if (existingUrls.indexOf(url) < 0) {
          existingUrls.push(url);
        }
      }
    } else {
      this.devices.push(device);
    }
  }

  removeDevice(index: number): void {
    this.devices.splice(index, 1);
  }

  getDeviceIndexByName(name: string): number {
    for (let i: number = 0; i < this.devices.length; i++) {
      if (this.devices[i].name === name) return i;
    }
    return -1;
  }
}

export const HostStore: HostStoreModel = new HostStoreModel();
