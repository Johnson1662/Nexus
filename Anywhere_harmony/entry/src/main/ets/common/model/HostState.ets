import { DeviceEntry } from './WorkspaceInfo';

export class HostPhase {
  static readonly UNKNOWN: string = 'unknown';
  static readonly CONNECTING: string = 'connecting';
  static readonly WAITING_HOST: string = 'waiting_host';
  static readonly ONLINE: string = 'online';
  static readonly OFFLINE: string = 'offline';
  static readonly RECONNECTING: string = 'reconnecting';
  static readonly SYNCING: string = 'syncing';
  static readonly ERROR: string = 'error';
}

@ObservedV2
export class HostRuntimeState {
  @Trace hostKey: string = '';
  @Trace phase: string = HostPhase.UNKNOWN;
  @Trace activeUrl: string = '';
  @Trace lastSeenAt: number = 0;
  @Trace lastAttemptAt: number = 0;
  @Trace retryAttempt: number = 0;
  @Trace latencyMs: number = -1;
  @Trace lastError: string = '';
  @Trace everOnline: boolean = false;
}

@ObservedV2
export class HostRuntimeStoreModel {
  @Trace statuses: HostRuntimeState[] = [];
  @Trace activeHostKey: string = '';

  getHostKey(device: DeviceEntry): string {
    return device.hostId || device.name;
  }

  getStatus(hostKey: string): HostRuntimeState {
    for (let i: number = 0; i < this.statuses.length; i++) {
      if (this.statuses[i].hostKey === hostKey) {
        return this.statuses[i];
      }
    }
    let status = new HostRuntimeState();
    status.hostKey = hostKey;
    this.statuses.push(status);
    this.statuses = [...this.statuses];
    return status;
  }

  getPhase(hostKey: string): string {
    if (hostKey.length === 0) return HostPhase.UNKNOWN;
    return this.getStatus(hostKey).phase;
  }

  setPhase(hostKey: string, phase: string, detail: string = ''): void {
    if (hostKey.length === 0) return;
    let status: HostRuntimeState = this.getStatus(hostKey);
    status.phase = phase;
    if (detail.length > 0) {
      status.lastError = detail;
    }
    if (phase === HostPhase.CONNECTING || phase === HostPhase.WAITING_HOST || phase === HostPhase.RECONNECTING) {
      status.lastAttemptAt = Date.now();
    }
    if (phase === HostPhase.ONLINE || phase === HostPhase.SYNCING) {
      status.lastSeenAt = Date.now();
    }
    this.statuses = [...this.statuses];
  }

  markConnecting(hostKey: string, url: string): void {
    if (hostKey.length === 0) return;
    this.activeHostKey = hostKey;
    let status: HostRuntimeState = this.getStatus(hostKey);
    status.activeUrl = url;
    status.retryAttempt = 0;
    status.latencyMs = -1;
    status.lastError = '';
    status.lastAttemptAt = Date.now();
    status.phase = HostPhase.CONNECTING;
    this.statuses = [...this.statuses];
  }

  markWaitingHost(hostKey: string, url: string): void {
    if (hostKey.length === 0) return;
    this.activeHostKey = hostKey;
    let status: HostRuntimeState = this.getStatus(hostKey);
    status.activeUrl = url;
    status.lastAttemptAt = Date.now();
    status.phase = HostPhase.WAITING_HOST;
    this.statuses = [...this.statuses];
  }

  markOnline(hostKey: string, url: string, latencyMs: number = -1): void {
    if (hostKey.length === 0) return;
    this.activeHostKey = hostKey;
    let status: HostRuntimeState = this.getStatus(hostKey);
    status.activeUrl = url;
    status.latencyMs = latencyMs;
    status.retryAttempt = 0;
    status.lastError = '';
    status.lastSeenAt = Date.now();
    status.everOnline = true;
    status.phase = HostPhase.ONLINE;
    this.statuses = [...this.statuses];
  }

  markOffline(hostKey: string, reason: string): void {
    if (hostKey.length === 0) return;
    let status: HostRuntimeState = this.getStatus(hostKey);
    status.lastError = reason;
    status.phase = HostPhase.OFFLINE;
    this.statuses = [...this.statuses];
  }

  markReconnecting(hostKey: string, attempt: number, reason: string = ''): void {
    if (hostKey.length === 0) return;
    this.activeHostKey = hostKey;
    let status: HostRuntimeState = this.getStatus(hostKey);
    status.retryAttempt = attempt;
    status.lastAttemptAt = Date.now();
    if (reason.length > 0) {
      status.lastError = reason;
    }
    status.phase = HostPhase.RECONNECTING;
    this.statuses = [...this.statuses];
  }

  markSyncing(hostKey: string): void {
    this.setPhase(hostKey, HostPhase.SYNCING);
  }

  markError(hostKey: string, reason: string): void {
    this.setPhase(hostKey, HostPhase.ERROR, reason);
  }

  isOnline(hostKey: string): boolean {
    let phase: string = this.getPhase(hostKey);
    return phase === HostPhase.ONLINE || phase === HostPhase.SYNCING;
  }

  getDevicePhase(device: DeviceEntry): string {
    let hostId: string = device.hostId || '';
    let name: string = device.name;
    if (hostId.length > 0 && this.isOnline(hostId)) {
      return this.getPhase(hostId);
    }
    if (name.length > 0 && this.isOnline(name)) {
      return this.getPhase(name);
    }
    if (this.isOnline(this.activeHostKey) && this.matchesDevice(device, this.activeHostKey)) {
      return this.getPhase(this.activeHostKey);
    }
    if (hostId.length > 0) {
      let hostPhase: string = this.getPhase(hostId);
      if (hostPhase !== HostPhase.UNKNOWN) return hostPhase;
    }
    if (name.length > 0) {
      return this.getPhase(name);
    }
    return HostPhase.UNKNOWN;
  }

  isDeviceOnline(device: DeviceEntry): boolean {
    let phase: string = this.getDevicePhase(device);
    return phase === HostPhase.ONLINE || phase === HostPhase.SYNCING;
  }

  matchesDevice(device: DeviceEntry, hostKey: string): boolean {
    if (hostKey.length === 0) return false;
    if (device.hostId === hostKey || device.name === hostKey) return true;
    let activeUrl: string = this.getStatus(hostKey).activeUrl;
    if (activeUrl.length === 0) return false;
    for (let i: number = 0; i < device.urls.length; i++) {
      if (device.urls[i] === activeUrl || activeUrl.indexOf(device.urls[i]) >= 0 || device.urls[i].indexOf(activeUrl) >= 0) {
        return true;
      }
    }
    return false;
  }

  isCurrentHost(hostKey: string): boolean {
    return hostKey.length > 0 && this.activeHostKey === hostKey;
  }

  isCurrentHostOnline(hostKey: string): boolean {
    return this.isCurrentHost(hostKey) && this.isOnline(hostKey);
  }

  hasEverOnline(hostKey: string): boolean {
    if (hostKey.length === 0) return false;
    return this.getStatus(hostKey).everOnline;
  }

  mergeHostKey(oldKey: string, newKey: string): void {
    if (oldKey.length === 0 || newKey.length === 0 || oldKey === newKey) return;
    let oldStatus: HostRuntimeState = this.getStatus(oldKey);
    let newStatus: HostRuntimeState = this.getStatus(newKey);
    newStatus.phase = oldStatus.phase;
    newStatus.activeUrl = oldStatus.activeUrl;
    newStatus.lastSeenAt = oldStatus.lastSeenAt;
    newStatus.lastAttemptAt = oldStatus.lastAttemptAt;
    newStatus.retryAttempt = oldStatus.retryAttempt;
    newStatus.latencyMs = oldStatus.latencyMs;
    newStatus.lastError = oldStatus.lastError;
    newStatus.everOnline = oldStatus.everOnline || newStatus.everOnline;
    for (let i: number = this.statuses.length - 1; i >= 0; i--) {
      if (this.statuses[i].hostKey === oldKey) {
        this.statuses.splice(i, 1);
      }
    }
    if (this.activeHostKey === oldKey) {
      this.activeHostKey = newKey;
    }
    this.statuses = [...this.statuses];
  }
}

export const HostRuntimeStore: HostRuntimeStoreModel = new HostRuntimeStoreModel();
