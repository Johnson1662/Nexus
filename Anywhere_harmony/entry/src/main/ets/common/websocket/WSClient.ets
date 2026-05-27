import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { ChatStore } from '../model/ChatState';
import { ServerSession, HostStore, DeviceEntry } from '../model/WorkspaceInfo';
import { StorageService, PrefsKeys, saveHosts, loadWorkspaces, saveModelCache, saveSessionCache } from '../../services/StorageService';
import { WorkspaceStore } from '../model/WorkspaceInfo';
import { ClientMessage, ServerMessage, AcpUpdate, AgentInfo, ServerInfoMessage, SyncResponseMessage, SyncResponseEntry } from './WSProtocol';
import { getOrCreateClientKeyPair, signWithClientKey, generateEphemeralKeyPair } from './CryptoHelper';
import { PhoneEncryptedChannel } from './PhoneEncryptedChannel';

import { ModelItem, ModeItem } from '../model/ChatState';

const DOMAIN: number = 0x0000;
const TAG: string = 'WSClient';

export type StateChangeCallback = (connected: boolean, detail: string) => void;
export type ModelListCallback = (models: ModelItem[], modes: ModeItem[]) => void;
export type SessionListCallback = (sessions: ServerSession[]) => void;
export type AcpUpdateCallback = (update: AcpUpdate) => void;
export type AgentListCallback = (agents: AgentInfo[]) => void;
export type ErrorCallback = (text: string) => void;
export type EmptyCallback = () => void;

export class WSClient {
  private ws: webSocket.WebSocket | null = null;
  private stateListeners: StateChangeCallback[] = [];
  private modelListeners: ModelListCallback[] = [];
  private sessionListeners: SessionListCallback[] = [];
  private updateListeners: AcpUpdateCallback[] = [];
  private agentListListeners: AgentListCallback[] = [];
  private errorListeners: ErrorCallback[] = [];
  private sessionStartedListeners: EmptyCallback[] = [];
  private lastUrl: string = '';
  private reconnectTimer: number | null = null;
  private reconnectAttempts: number = 0;
  private intentionalClose: boolean = false;
  private suspendRequestId: number | null = null;
  private wsGen: number = 0;
  private everConnected: boolean = false;
  private _e2eeReady: boolean = false;
  private _e2eeClientId: string = '';
  private channel: PhoneEncryptedChannel = new PhoneEncryptedChannel();
  // Heartbeat state (Phase 2b)
  private lastHeartbeatReceived: number = 0;
  private heartbeatWatchdog: number | null = null;
  private readonly HEARTBEAT_WATCHDOG_MS: number = 45_000;  // 45s no heartbeat → disconnect

  connect(url: string): void {
    this.cancelReconnect();
    this.lastUrl = url;
    this.intentionalClose = false;
    this.reconnectAttempts = 0;
    this.everConnected = false;
    this.doConnect(url);
  }

  // Try connecting to a single URL, returns latency in ms on success, -1 on failure
  tryConnect(url: string): Promise<number> {
    return new Promise<number>((resolve) => {
      let start: number = Date.now();
      let resolved: boolean = false;
      let ws: webSocket.WebSocket = webSocket.createWebSocket();
      let timer: number | null = null;

      let done = (latency: number): void => {
        if (resolved) return;
        resolved = true;
        if (timer !== null) {
          clearTimeout(timer);
          timer = null;
        }
        ws.off('open'); ws.off('error'); ws.off('close');
        try { ws.close(); } catch {}
        resolve(latency);
      };

      timer = setTimeout(() => { done(-1) }, 3000);

      ws.on('open', () => { done(Date.now() - start) });
      ws.on('error', () => { done(-1) });
      ws.on('close', () => { done(-1) });

      try {
        ws.connect(url);
      } catch {
        done(-1);
      }
    });
  }

  // Connect to the fastest reachable URL from a device, then use that URL
  async connectBest(urls: string[]): Promise<void> {
    let bestUrl: string = urls[0];
    let bestLatency: number = -1;
    let results: Promise<number>[] = [];
    for (let i: number = 0; i < urls.length; i++) {
      results.push(this.tryConnect(urls[i]));
    }
    for (let i: number = 0; i < results.length; i++) {
      let latency: number = await results[i];
      if (latency >= 0 && (bestLatency < 0 || latency < bestLatency)) {
        bestLatency = latency;
        bestUrl = urls[i];
      }
    }
    hilog.info(DOMAIN, TAG, `connectBest: selected ${bestUrl} (${bestLatency}ms)`);
    this.connect(bestUrl);
  }

  private doConnect(url: string): void {
    this.disconnectInternal();
    this.ws = webSocket.createWebSocket();
    let gen: number = ++this.wsGen;
    let connectNotified: boolean = false;
    let connectTimeout = setTimeout(() => {
      if (!connectNotified) {
        onConnectFailure('Connect timeout (10s)');
      }
    }, 10000);

    let onConnectFailure = (detail: string): void => {
      if (connectNotified) return;
      connectNotified = true;
      clearTimeout(connectTimeout);
      hilog.error(DOMAIN, TAG, detail);
      ChatStore.connected = false;
      this.notifyState(false, detail);
      if (!this.intentionalClose) {
        this.scheduleReconnect();
      }
    };

    this.ws.on('open', () => {
      if (gen !== this.wsGen) return;
      clearTimeout(connectTimeout);
      connectNotified = true;
      this.everConnected = true;
      hilog.info(DOMAIN, TAG, 'connected: ' + url);
      ChatStore.connected = true;
      ChatStore.reconnectAttempt = 0;
      this.reconnectAttempts = 0;
      this.notifyState(true, url);
      this.requestBgTask();
      // Start heartbeat watchdog
      this.startHeartbeatWatchdog();
      // Phase 3b: Clear ghost permission overlay on reconnect
      ChatStore.pendingPermission = null;
      // Auto-initiate E2EE for relay connections (URL contains targetHostId)
      if (url.indexOf('targetHostId=') >= 0) {
        this.initiateE2EE(url, gen);
      }
      // Phase 3b + grill: Request cursor sync if we have a session (reconnect recovery)
      if (ChatStore.sessionId.length > 0 && ChatStore.lastMessageId.length > 0) {
        ChatStore.reconnectPhase = 'syncing';
        this.send({
          type: 'sync_request',
          sessionId: ChatStore.sessionId,
          lastMessageId: ChatStore.lastMessageId,
        } as ClientMessage);
      } else {
        // No session to sync — clear reconnect phase immediately
        ChatStore.reconnectPhase = '';
      }
    });

    this.ws.on('message', (_err: BusinessError, data: string | ArrayBuffer) => {
      if (typeof data === 'string') {
        this.handleMessage(data);
      } else if (data instanceof ArrayBuffer) {
        if (this._e2eeReady) {
          this.channel.decrypt(data).then((plainStr) => {
            this.handleMessage(plainStr);
          }).catch((err: Error) => {
            hilog.error(DOMAIN, TAG, 'decrypt failed: ' + JSON.stringify(err));
          });
        } else {
          // Before E2EE handshake, relay sends all frames as binary (opcode 0x02)
          // Convert ArrayBuffer to string for plaintext JSON handling
          let bytes: Uint8Array = new Uint8Array(data);
          let decoder: util.TextDecoder = new util.TextDecoder('utf-8', { ignoreBOM: true });
          let raw: string = decoder.decodeToString(bytes);
          this.handleMessage(raw);
        }
      }
    });


    this.ws.on('close', () => {
      if (gen !== this.wsGen) return;
      if (!this.everConnected) {
        onConnectFailure('Connection closed before WebSocket handshake completed');
        return;
      }
      this.everConnected = false;
      hilog.info(DOMAIN, TAG, 'disconnected: ' + url);
      ChatStore.connected = false;
      this.cancelBgTask();
      this.notifyState(false, '');
      if (!this.intentionalClose) {
        ChatStore.reconnectPhase = 'disconnected';
        this.scheduleReconnect();
      }
    });

    this.ws.on('error', (err: BusinessError) => {
      if (gen !== this.wsGen) return;
      if (this.everConnected) {
        hilog.error(DOMAIN, TAG, 'post-connect error: ' + JSON.stringify(err));
        return;
      }
      onConnectFailure('Connection error: ' + JSON.stringify(err));
    });

    this.ws.connect(url, (err: BusinessError) => {
      if (gen !== this.wsGen) return;
      if (err) {
        onConnectFailure('Connect failed: ' + JSON.stringify(err));
      }
    });
  }

  private scheduleReconnect(): void {
    if (this.intentionalClose || !this.lastUrl) return;
    this.cancelReconnect();
    this.everConnected = false;
    this.reconnectAttempts++;
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts - 1), 30000);
    hilog.info(DOMAIN, TAG, `reconnect in ${delay}ms (attempt ${this.reconnectAttempts})`);
    ChatStore.reconnectPhase = 'reconnecting';
    ChatStore.reconnectAttempt = this.reconnectAttempts;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this.doConnect(this.lastUrl);
    }, delay);
  }

  private cancelReconnect(): void {
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
  }

  private requestBgTask(): void {
    try {
      const info = backgroundTaskManager.requestSuspendDelay('Keep WebSocket alive', () => {
        hilog.info(DOMAIN, TAG, 'bg task about to expire');
      });
      this.suspendRequestId = info.requestId;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'bg task failed: ' + JSON.stringify(err));
    }
  }

  private cancelBgTask(): void {
    if (this.suspendRequestId !== null) {
      try {
        backgroundTaskManager.cancelSuspendDelay(this.suspendRequestId);
      } catch {}
      this.suspendRequestId = null;
    }
  }

  send(msg: ClientMessage): void {
    if (!this.ws) {
      return;
    }
    try {
      if (this._e2eeReady && this.channel.isReady()) {
        this.channel.encrypt(JSON.stringify(msg)).then((frame) => {
          this.ws?.send(frame);
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'encrypt failed: ' + JSON.stringify(err));
        });
      } else {
        this.ws.send(JSON.stringify(msg));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'send failed: ' + JSON.stringify(err));
    }

  }
  /** 发送控制消息（E2EE 握手/心跳等 text frame） */
  sendControl(type: string, payload: Record<string, Object>): void {
    if (!this.ws) return;
    try {
      let data: Record<string, Object> = {};
      data['type'] = type;
      if (type === 'e2ee_hello' && payload['ephemeralKey']) {
        data['channelId'] = String(payload['ephemeralKey']).slice(0, 16);
      }
      let keys: string[] = Object.keys(payload);
      for (let i: number = 0; i < keys.length; i++) {
        data[keys[i]] = payload[keys[i]] as Object;
      }
      this.ws.send(JSON.stringify(data));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'sendControl failed: ' + JSON.stringify(err));
    }
  }
  private async initiateE2EE(url: string, gen: number): Promise<void> {
    try {
      const hostEd25519PubKey: string = AppStorage.get<string>('hostEd25519PublicKey') || '';
      const hostId: string = AppStorage.get<string>('hostId') || '';
      if (!hostEd25519PubKey || !hostId) return;

      let ephKeyPair = await generateEphemeralKeyPair();
      let clientKeyPair = await getOrCreateClientKeyPair();
      let clientId: string = hostId + '_client_' + Date.now();
      this._e2eeClientId = clientId;

      let signPayload: string = hostId + ephKeyPair.publicKeyHex + clientId;
      let signature: string = await signWithClientKey(signPayload);

      let helloPayload: Record<string, Object> = {};
      helloPayload['protocolVersion'] = 1;
      helloPayload['clientId'] = clientId;
      helloPayload['clientPublicKey'] = clientKeyPair.publicKeyHex;
      helloPayload['ephemeralKey'] = ephKeyPair.publicKeyHex;
      helloPayload['hostId'] = hostId;
      helloPayload['signature'] = signature;
      this.sendControl('e2ee_hello', helloPayload);
      hilog.info(DOMAIN, TAG, 'E2EEHello sent');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'initiateE2EE failed: ' + JSON.stringify(err));
    }
  }

  disconnect(): void {
    this.intentionalClose = true;
    this.everConnected = false;
    this.cancelReconnect();
    this.cancelBgTask();
    this.disconnectInternal();
  }

  private disconnectInternal(): void {
    if (this.ws) {
      try {
        this.ws.close();
      } catch {}
      this.ws = null;
    }
    ChatStore.connected = false;
    this.stopHeartbeatWatchdog();
  }

  onStateChange(cb: StateChangeCallback): void {
    this.stateListeners.push(cb);
  }
  onModelList(cb: ModelListCallback): void {
    this.modelListeners.push(cb);
  }
  onSessionList(cb: SessionListCallback): void {
    this.sessionListeners.push(cb);
  }
  onAcpUpdate(cb: AcpUpdateCallback): void {
    this.updateListeners.push(cb);
  }
  onAgentList(cb: AgentListCallback): void {
    this.agentListListeners.push(cb);
  }
  onError(cb: ErrorCallback): void {
    this.errorListeners.push(cb);
  }
  onSessionStarted(cb: EmptyCallback): void {
    this.sessionStartedListeners.push(cb);
  }

  clearListeners(): void {
    this.stateListeners = [];
    this.modelListeners = [];
    this.sessionListeners = [];
    this.agentListListeners = [];
    this.errorListeners = [];
    this.sessionStartedListeners = [];
  }

  sendPermissionResponse(optionId: string): void {
    if (!ChatStore.pendingPermission) return;
    let reqId: string = ChatStore.pendingPermission.requestId;
    let sessionId: string = ChatStore.sessionId;
    this.send({
      type: 'permission_response',
      sessionId: sessionId,
      requestId: reqId,
      outcome: 'selected',
      optionId: optionId,
    } as ClientMessage);
    ChatStore.pendingPermission = null;
  }

  private parsePermissionOptions(raw: Object | undefined): import('../model/ChatState').PermissionOption[] {
    if (!raw) return [];
    let arr: Array<Record<string, Object>> = raw as Array<Record<string, Object>>;
    let result: import('../model/ChatState').PermissionOption[] = [];
    for (let i = 0; i < arr.length; i++) {
      result.push({
        optionId: String(arr[i]['optionId']) || '',
        name: String(arr[i]['name']) || '',
        kind: String(arr[i]['kind']) || '',
      });
    }
    return result;
  }

  private notifyState(connected: boolean, detail: string = ''): void {
    for (let cb of this.stateListeners) {
      cb(connected, detail);
    }
  }

  private handleServerInfo(info: ServerInfoMessage): void {
    let hostname: string = info.hostname;
    let connectedUrl: string = this.lastUrl;
    if (connectedUrl.length === 0) return;
    // Strip query parameters (e.g. from QR code relay URL) for device persistence
    let qIdx: number = connectedUrl.indexOf('?');
    let cleanUrl: string = qIdx >= 0 ? connectedUrl.substring(0, qIdx) : connectedUrl;
    // Dedup: remove all existing devices with same hostId or same hostname
    let mergedUrls: string[] = [];
    for (let i: number = HostStore.devices.length - 1; i >= 0; i--) {
      let d = HostStore.devices[i];
      let match: boolean = false;
      if (info.hostId && d.hostId === info.hostId) {
        match = true;
      } else if (d.name === hostname) {
        // Same hostname = same device (regardless of hostId)
        match = true;
      }
      if (match) {
        for (let j: number = 0; j < d.urls.length; j++) {
          if (mergedUrls.indexOf(d.urls[j]) < 0) mergedUrls.push(d.urls[j]);
        }
        HostStore.removeDevice(i);
      }
    }
    if (mergedUrls.indexOf(cleanUrl) < 0) mergedUrls.push(cleanUrl);
    HostStore.addOrUpdateDevice({
      name: hostname,
      urls: mergedUrls,
      hostId: info.hostId,
      relayPin: info.relayPin,
    } as DeviceEntry);

    saveHosts();
    loadWorkspaces(connectedUrl);
  }

  private handleE2EEMessage(raw: string): void {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(raw) as Record<string, Object>;
    } catch { return; }
    let type: string = String(parsed['type'] || '');
    if (type === 'e2ee_ready') {
      let accepted: boolean = Boolean(parsed['accepted']);
      if (accepted) {
        hilog.info(DOMAIN, TAG, 'E2EE handshake completed');
        const ephHostHex = String(parsed['ephemeralKey'] || '');
        const hostSignature = String(parsed['signature'] || '');
        import('./CryptoHelper').then((module) => {
          module.finishE2EEHandshake(ephHostHex, hostSignature, this._e2eeClientId).then((res) => {
            if (res) {
              this._e2eeReady = true;
              this.setE2EEKey(res.aesKey, res.channelIdHex);
              hilog.info(DOMAIN, TAG, 'AES key established');
            }
          }).catch((err: Error) => hilog.error(DOMAIN, TAG, 'Handshake error: ' + JSON.stringify(err)));
        });
      } else {
        let error: string = String(parsed['error'] || 'unknown');
        hilog.error(DOMAIN, TAG, 'E2EE handshake rejected: ' + error);
        // Q6 grill: propagate specific failure reason to UI
        this.notifyState(false, 'E2EE握手拒绝: ' + error);
      }
    }
  }

  // Set the AES key when handshake completes
  public setE2EEKey(key: Uint8Array, channelIdHex: string) {
    this.channel.setAesKey(key, channelIdHex);
  }

  // ── Heartbeat (Phase 2b) ─────────────────────────────────────────

  private startHeartbeatWatchdog(): void {
    this.lastHeartbeatReceived = Date.now();
    this.stopHeartbeatWatchdog();
    this.heartbeatWatchdog = setInterval(() => {
      if (Date.now() - this.lastHeartbeatReceived > this.HEARTBEAT_WATCHDOG_MS) {
        hilog.error(DOMAIN, TAG, 'Heartbeat timeout (45s), disconnecting');
        this.intentionalClose = false;
        this.disconnectInternal();
        this.scheduleReconnect();
      }
    }, 15_000);
  }

  private stopHeartbeatWatchdog(): void {
    if (this.heartbeatWatchdog !== null) {
      clearInterval(this.heartbeatWatchdog);
      this.heartbeatWatchdog = null;
    }
  }

  private handleHeartbeat(payload: Record<string, Object>): void {
    this.lastHeartbeatReceived = Date.now();
    // Reply with same timestamp, avoiding duplicate type field
    let hbPayload: Record<string, Object> = {};
    hbPayload['ts'] = payload['ts'];
    this.sendControl('heartbeat', hbPayload);
  }


  private handleMessage(raw: string): void {
    // Intercept heartbeat control messages before E2EE handling
    if (raw.indexOf('"heartbeat"') >= 0 && raw.indexOf('"ts"') >= 0) {
      try {
        const hb = JSON.parse(raw) as Record<string, Object>;
        if (hb['type'] === 'heartbeat') {
          this.handleHeartbeat(hb as Record<string, Object>);
          return;
        }
      } catch {}
    }

    // E2EE handshake messages are intercepted at control level
    if (raw.indexOf('"e2ee_hello"') >= 0 || raw.indexOf('"e2ee_ready"') >= 0) {
      this.handleE2EEMessage(raw);
      return;
    }

    let msg: ServerMessage;
    try {
      msg = JSON.parse(raw) as ServerMessage;
    } catch {
      return;
    }
    switch (msg.type) {
      case 'server_info':
        this.handleServerInfo(msg as ServerInfoMessage);
        break;
      case 'session_started':
        ChatStore.sessionId = msg.sessionId || '';
        if (msg.loadedSessionId) {
          ChatStore.loadedSessionId = msg.loadedSessionId;
        } else {
          ChatStore.loadedSessionId = '';
        }
        if (msg.model) {
          ChatStore.sessionCurrentModelId = msg.model;
          ChatStore.lastModelId = msg.model;
          StorageService.getInstance().putString(PrefsKeys.LAST_MODEL_ID, msg.model);
          for (let i = 0; i < ChatStore.models.length; i++) {
            if (ChatStore.models[i].modelId === msg.model) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
        if (msg.title) {
          ChatStore.sessionTitle = msg.title;
        }
        {
          let id = msg.loadedSessionId || msg.sessionId || '';
          let found = false;
          for (let i = 0; i < ChatStore.sessions.length; i++) {
            if (ChatStore.sessions[i].sessionId === id) {
              ChatStore.sessions[i].title = String(msg.title || ChatStore.sessions[i].title);
              found = true;
              break;
            }
          }
          if (!found) {
            let s = new ServerSession();
            s.sessionId = id;
            s.title = String(msg.title || '');
            ChatStore.sessions = [...ChatStore.sessions, s];
          }
        }
        ChatStore.sessionReady = true;
        for (let cb of this.sessionStartedListeners) {
          cb();
        }
        break;
      case 'agent_event':
        if (msg.event) {
          for (let cb of this.updateListeners) {
            cb(msg.event);
          }
        }
        break;
      case 'turn_ended':
        ChatStore.turnActive = false;
        {
          let u: AcpUpdate = { sessionUpdate: 'turn_ended' };
          for (let cb of this.updateListeners) {
            cb(u);
          }
        }
        break;
      case 'model_list':
        ChatStore.models = msg.models || [];
        ChatStore.modes = msg.modes || [];
        if (ChatStore.sessionCurrentModelId) {
          for (let i = 0; i < ChatStore.models.length; i++) {
            if (ChatStore.models[i].modelId === ChatStore.sessionCurrentModelId) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
        // If session didn't set a model, try persisted lastModelId
        if (!ChatStore.sessionCurrentModelId && ChatStore.lastModelId.length > 0) {
          for (let i = 0; i < ChatStore.models.length; i++) {
            if (ChatStore.models[i].modelId === ChatStore.lastModelId) {
              ChatStore.modelIndex = i;
              break;
            }
          }
        }
        // Persist to local cache
        saveModelCache(ChatStore.agentType || ChatStore.selectedAgentName, msg.models || [], msg.modes || []);
        for (let cb of this.modelListeners) {
          cb(msg.models || [], msg.modes || []);
        }
        break;
      case 'session_list':
        ChatStore.sessions = msg.sessions || [];
        ChatStore.sessionReady = true;
        // Persist to local cache
        if (ChatStore.agentType.length > 0 && WorkspaceStore.currentIndex >= 0 &&
            WorkspaceStore.currentIndex < WorkspaceStore.workspaces.length) {
          let cwd: string = WorkspaceStore.workspaces[WorkspaceStore.currentIndex].path;
          saveSessionCache(ChatStore.agentType, cwd, msg.sessions || []);
        }
        for (let cb of this.sessionListeners) {
          cb(msg.sessions || []);
        }
        break;
      case 'agent_list':
        for (let cb of this.agentListListeners) {
          cb(msg.agents || []);
        }
        break;
      case 'error':
        for (let cb of this.errorListeners) {
          cb(String(msg.text || 'Unknown error'));
        }
        break;
      case 'permission_request':
        if (msg.requestId && msg.toolCall) {
          let toolCall: Record<string, Object> = msg.toolCall as Record<string, Object>;
          ChatStore.pendingPermission = {
            requestId: msg.requestId,
            toolCall: {
              toolCallId: String(toolCall['toolCallId']) || '',
              title: String(toolCall['title']) || '',
              kind: String(toolCall['kind']) || '',
            },
            options: this.parsePermissionOptions(msg.options),
          };
        }
        break;
      case 'config_option_updated':
        if (msg.configOptions) {
          ChatStore.configOptions = msg.configOptions;
        }
        break;
      case 'session_closed':
        ChatStore.sessionId = '';
        ChatStore.messages = [];
        ChatStore.planEntries = [];
        ChatStore.sessionTitle = '';
        ChatStore.configOptions = [];
        break;
      // Phase 3b: Cursor sync response (reconnect recovery)
      case 'sync_response': {
        let syncMsg: SyncResponseMessage = msg as SyncResponseMessage;
        let entries: Array<SyncResponseEntry> | undefined = syncMsg.entries;
        hilog.info(DOMAIN, TAG, 'sync_response: ' + (entries !== undefined ? String(entries.length) : '0') + ' entries');
        if (entries !== undefined) {
          for (let i = 0; i < entries.length; i++) {
            let entry: SyncResponseEntry = entries[i];
            let payload: AcpUpdate | undefined = entry.payload;
            if (payload !== undefined && payload.sessionUpdate !== undefined) {
              // Defensive dedup: skip entries already processed
              if (payload.messageId !== undefined && payload.messageId === ChatStore.lastMessageId) continue;
              for (let cb of this.updateListeners) {
                cb(payload);
              }
              if (payload.messageId !== undefined) {
                ChatStore.lastMessageId = String(payload.messageId);
              }
            }
          }
          // Phase transition: syncing → normal (complete)
          ChatStore.reconnectPhase = '';
          hilog.info(DOMAIN, TAG, 'sync_response: processed ' + String(entries.length) + ' entries');
        }
        break;
      }
      default:
        hilog.info(DOMAIN, TAG, 'unhandled: ' + msg.type);
        break;
    }
  }
}
