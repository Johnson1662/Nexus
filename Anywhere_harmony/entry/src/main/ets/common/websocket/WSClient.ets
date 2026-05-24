import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { ChatStore } from '../model/ChatState';
import { ServerSession, HostStore, DeviceEntry } from '../model/WorkspaceInfo';
import { StorageService, PrefsKeys, saveHosts, loadWorkspaces, saveModelCache, saveSessionCache } from '../../services/StorageService';
import { WorkspaceStore } from '../model/WorkspaceInfo';
import { ClientMessage, ServerMessage, AcpUpdate, AgentInfo, ServerInfoMessage } from './WSProtocol';
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

    let onConnectFailure = (detail: string): void => {
      if (connectNotified) return;
      connectNotified = true;
      hilog.error(DOMAIN, TAG, detail);
      ChatStore.connected = false;
      this.notifyState(false, detail);
      if (!this.intentionalClose) {
        this.scheduleReconnect();
      }
    };

    this.ws.on('open', () => {
      if (gen !== this.wsGen) return;
      connectNotified = true;
      this.everConnected = true;
      hilog.info(DOMAIN, TAG, 'connected: ' + url);
      ChatStore.connected = true;
      this.reconnectAttempts = 0;
      this.notifyState(true, url);
      this.requestBgTask();
    });

    this.ws.on('message', (_err: BusinessError, data: string | ArrayBuffer) => {
      if (typeof data === 'string') {
        this.handleMessage(data);
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
      this.ws.send(JSON.stringify(msg));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'send failed: ' + JSON.stringify(err));
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
    this.updateListeners = [];
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
    // Only add the actual connected URL — name-matched merge with existing device
    HostStore.addOrUpdateDevice({ name: hostname, urls: [connectedUrl] } as DeviceEntry);
    // Remove stale entries that share this URL but have a different name (e.g. migrated old ip:port format)
    for (let i: number = HostStore.devices.length - 1; i >= 0; i--) {
      if (HostStore.devices[i].name !== hostname && HostStore.devices[i].urls.indexOf(connectedUrl) >= 0) {
        HostStore.removeDevice(i);
      }
    }
    saveHosts();
    loadWorkspaces(connectedUrl);
  }

  private handleMessage(raw: string): void {
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
      default:
        hilog.info(DOMAIN, TAG, 'unhandled: ' + msg.type);
        break;
    }
  }
}
