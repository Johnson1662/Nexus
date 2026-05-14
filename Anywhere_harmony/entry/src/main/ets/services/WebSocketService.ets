import { webSocket } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlanEntry, ServerSession } from '../store/SessionStore';

const DOMAIN: number = 0x0000;
const TAG: string = 'WebSocketService';

export interface AgentContent {
  text?: string;
}

export interface ToolCallInfo {
  title?: string;
}

export interface SessionUpdateData {
  type: string;
  content?: AgentContent;
  toolCallId?: string;
  title?: string;
  status?: string;
  entries?: PlanEntry[];
}

export interface AgentEvent {
  sessionUpdate?: SessionUpdateData;
  content?: AgentContent;
  toolCallId?: string;
  title?: string;
  status?: string;
  entries?: PlanEntry[];
}

export interface ModelInfo {
  modelId: string;
  name: string;
}

export interface ModeInfo {
  value: string;
  name: string;
}

export interface WebSocketMessage {
  type: string;
  sessionId?: string;
  loadedSessionId?: string;
  agent?: string;
  model?: string;
  modeId?: string;
  prompt?: string;
  text?: string;
  cwd?: string;
  event?: AgentEvent;
  stopReason?: string;
  exitCode?: number;
  requestId?: string;
  toolCall?: ToolCallInfo;
  outcome?: string;
  sessions?: ServerSession[];
  models?: ModelInfo[];
  modes?: ModeInfo[];
}

type MessageListener = (msg: WebSocketMessage) => void;
type StateListener = (connected: boolean) => void;

export class WebSocketService {
  private ws: webSocket.WebSocket | null = null;
  private messageListeners: MessageListener[] = [];
  private stateListeners: StateListener[] = [];
  private connected: boolean = false;

  connect(url: string): void {
    hilog.info(DOMAIN, TAG, 'Connecting to %{public}s', url);
    this.ws = webSocket.createWebSocket();

    this.ws.on('open', () => {
      hilog.info(DOMAIN, TAG, 'Connected');
      this.connected = true;
      this.notifyStateChange(true);
    });

    this.ws.on('message', (err, data: string | ArrayBuffer) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'Message error: %{public}s', JSON.stringify(err));
        return;
      }
      if (typeof data === 'string') {
        try {
          let msg: WebSocketMessage = JSON.parse(data) as WebSocketMessage;
          this.notifyMessage(msg);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'Failed to parse message: %{public}s', JSON.stringify(err));
        }
      }
    });

    this.ws.on('close', () => {
      hilog.info(DOMAIN, TAG, 'Connection closed');
      this.connected = false;
      this.notifyStateChange(false);
    });

    this.ws.on('error', (err) => {
      hilog.error(DOMAIN, TAG, 'WebSocket error: %{public}s', JSON.stringify(err));
      this.connected = false;
      this.notifyStateChange(false);
    });

    this.ws.connect(url);
  }

  send(msg: WebSocketMessage): void {
    if (!this.connected || this.ws === null) {
      hilog.warn(DOMAIN, TAG, 'Cannot send: not connected');
      return;
    }

    try {
      this.ws.send(JSON.stringify(msg));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Send error: %{public}s', JSON.stringify(err));
    }
  }

  onMessage(listener: MessageListener): void {
    this.messageListeners.push(listener);
  }

  onStateChange(listener: StateListener): void {
    this.stateListeners.push(listener);
  }

  disconnect(): void {
    if (this.ws !== null) {
      this.ws.close();
      this.ws = null;
    }
    this.connected = false;
  }

  private notifyMessage(msg: WebSocketMessage): void {
    for (let listener of this.messageListeners) {
      listener(msg);
    }
  }

  private notifyStateChange(connected: boolean): void {
    for (let listener of this.stateListeners) {
      listener(connected);
    }
  }
}
