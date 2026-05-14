import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ChatStore } from '../model/ChatState';
import { ServerSession } from '../model/WorkspaceInfo';
import { ClientMessage, ServerMessage, AcpUpdate, ModelItem, ModeItem, AgentInfo } from './WSProtocol';

const DOMAIN: number = 0x0000;
const TAG: string = 'WSClient';

export type StateChangeCallback = (connected: boolean) => void;
export type ModelListCallback = (models: ModelItem[], modes: ModeItem[]) => void;
export type SessionListCallback = (sessions: ServerSession[]) => void;
export type AcpUpdateCallback = (update: AcpUpdate) => void;
export type AgentListCallback = (agents: AgentInfo[]) => void;
export type EmptyCallback = () => void;

export class WSClient {
  private ws: webSocket.WebSocket | null = null;
  private stateListeners: StateChangeCallback[] = [];
  private modelListeners: ModelListCallback[] = [];
  private sessionListeners: SessionListCallback[] = [];
  private updateListeners: AcpUpdateCallback[] = [];
  private agentListListeners: AgentListCallback[] = [];
  private sessionStartedListeners: EmptyCallback[] = [];

  connect(url: string): void {
    this.disconnect();
    this.ws = webSocket.createWebSocket();

    this.ws.on('open', () => {
      hilog.info(DOMAIN, TAG, 'connected');
      ChatStore.connected = true;
      this.notifyState(true);
    });

    this.ws.on('message', (_err: BusinessError, data: string | ArrayBuffer) => {
      if (typeof data === 'string') {
        this.handleMessage(data);
      }
    });

    this.ws.on('close', () => {
      hilog.info(DOMAIN, TAG, 'disconnected');
      ChatStore.connected = false;
      this.notifyState(false);
    });

    this.ws.on('error', (err: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'error: ' + JSON.stringify(err));
      ChatStore.connected = false;
      this.notifyState(false);
    });

    this.ws.connect(url, (err: BusinessError) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'connect failed: ' + JSON.stringify(err));
        ChatStore.connected = false;
        this.notifyState(false);
      }
    });
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
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
    ChatStore.connected = false;
    this.notifyState(false);
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
  onSessionStarted(cb: EmptyCallback): void {
    this.sessionStartedListeners.push(cb);
  }

  clearListeners(): void {
    this.stateListeners = [];
    this.modelListeners = [];
    this.sessionListeners = [];
    this.updateListeners = [];
    this.agentListListeners = [];
    this.sessionStartedListeners = [];
  }

  private notifyState(connected: boolean): void {
    for (let cb of this.stateListeners) {
      cb(connected);
    }
  }

  private handleMessage(raw: string): void {
    let msg: ServerMessage;
    try {
      msg = JSON.parse(raw) as ServerMessage;
    } catch {
      return;
    }

    switch (msg.type) {
      case 'session_started':
        ChatStore.sessionId = msg.sessionId || '';
        if (msg.loadedSessionId) {
          ChatStore.loadedSessionId = msg.loadedSessionId;
        }
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
        for (let cb of this.modelListeners) {
          cb(msg.models || [], msg.modes || []);
        }
        break;
      case 'session_list':
        for (let cb of this.sessionListeners) {
          cb(msg.sessions || []);
        }
        break;
      case 'agent_list':
        for (let cb of this.agentListListeners) {
          cb(msg.agents || []);
        }
        break;
      default:
        hilog.info(DOMAIN, TAG, 'unhandled: ' + msg.type);
        break;
    }
  }
}
