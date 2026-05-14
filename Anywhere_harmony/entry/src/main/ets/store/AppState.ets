import { WorkspaceInfo, MessageData, PlanEntry, ServerSession } from './SessionStore';
import { ModelInfo, ModeInfo } from '../services/WebSocketService';

export interface ConnectionState {
  status: 'disconnected' | 'connecting' | 'connected';
  hostName: string;
  hostUrl: string;
}

@Observed
export class AppState {
  connection: ConnectionState = {
    status: 'disconnected',
    hostName: '',
    hostUrl: ''
  };
  
  workspaces: WorkspaceInfo[] = [];
  currentWorkspaceIndex: number = -1;
  workspaceSessions: Map<string, ServerSession[]> = new Map();
  
  currentSessionId: string = '';
  currentSessionTitle: string = '';
  messages: MessageData[] = [];
  planEntries: PlanEntry[] = [];
  turnActive: boolean = false;
  
  model: string = '';
  modelLabel: string = 'Default';
  cachedModels: ModelInfo[] = [];
  cachedModes: ModeInfo[] = [];
  currentModeIndex: number = 0;
  
  showDrawer: boolean = false;
  showSessionMenu: boolean = false;
  
  get isConnected(): boolean {
    return this.connection.status === 'connected';
  }
  
  get isConnecting(): boolean {
    return this.connection.status === 'connecting';
  }
  
  get hasActiveSession(): boolean {
    return this.currentSessionId.length > 0;
  }
  
  get canSendMessage(): boolean {
    return this.isConnected && !this.turnActive;
  }
  
  get currentWorkspace(): WorkspaceInfo | null {
    if (this.currentWorkspaceIndex < 0 || this.currentWorkspaceIndex >= this.workspaces.length) {
      return null;
    }
    return this.workspaces[this.currentWorkspaceIndex];
  }
  
  get hasWorkspace(): boolean {
    return this.workspaces.length > 0;
  }
  
  get currentWorkspaceSessions(): ServerSession[] {
    const ws = this.currentWorkspace;
    if (!ws) return [];
    return this.workspaceSessions.get(ws.path) || [];
  }
  
  addMessage(msg: MessageData): void {
    this.messages.push(msg);
  }
  
  appendToLastAssistantText(text: string): MessageData[] {
    const msgs = this.messages;
    if (msgs.length > 0) {
      const lastIndex = msgs.length - 1;
      const last = msgs[lastIndex];
      if (last.role === 'assistant' && last.type === 'text' && (!last.toolCallId || last.toolCallId === '')) {
        const updated: MessageData = {
          id: last.id,
          role: last.role,
          content: last.content + text,
          type: last.type,
          version: last.version + 1,
          timestamp: last.timestamp
        };
        const newArr: MessageData[] = [];
        for (let i = 0; i < msgs.length; i++) {
          newArr.push(i === lastIndex ? updated : msgs[i]);
        }
        this.messages = newArr;
        return newArr;
      }
    }
    
    let trimmed = text.trim();
    if (trimmed.length === 0) return this.messages;
    
    const newMsg: MessageData = {
      id: 'msg_' + Date.now().toString(),
      role: 'assistant',
      content: trimmed,
      type: 'text',
      version: 0,
      timestamp: Date.now()
    };
    this.messages.push(newMsg);
    return this.messages;
  }
  
  appendThinking(text: string): MessageData[] {
    const msgs = this.messages;
    if (msgs.length > 0) {
      const lastIndex = msgs.length - 1;
      const last = msgs[lastIndex];
      if (last.role === 'assistant' && last.type === 'thinking') {
        const updated: MessageData = {
          id: last.id,
          role: last.role,
          content: last.content + text,
          type: last.type,
          version: last.version + 1,
          timestamp: last.timestamp
        };
        const newArr: MessageData[] = [];
        for (let i = 0; i < msgs.length; i++) {
          newArr.push(i === lastIndex ? updated : msgs[i]);
        }
        this.messages = newArr;
        return newArr;
      }
    }
    
    const newMsg: MessageData = {
      id: 'think_' + Date.now().toString(),
      role: 'assistant',
      content: text,
      type: 'thinking',
      version: 0,
      timestamp: Date.now()
    };
    this.messages.push(newMsg);
    return this.messages;
  }
  
  updateToolStatus(toolCallId: string, status: string): MessageData[] {
    const msgs = this.messages;
    for (let i = 0; i < msgs.length; i++) {
      if (msgs[i].toolCallId === toolCallId) {
        const original = msgs[i];
        const updated: MessageData = {
          id: original.id,
          role: original.role,
          content: original.content,
          type: original.type,
          version: original.version + 1,
          timestamp: original.timestamp,
          toolName: original.toolName,
          toolStatus: status,
          toolCallId: original.toolCallId
        };
        const newArr: MessageData[] = [];
        for (let j = 0; j < msgs.length; j++) {
          newArr.push(j === i ? updated : msgs[j]);
        }
        this.messages = newArr;
        return newArr;
      }
    }
    return this.messages;
  }
  
  updatePlan(entries: PlanEntry[]): void {
    this.planEntries = entries;
  }
  
  resetSession(): void {
    this.currentSessionId = '';
    this.currentSessionTitle = '';
    this.messages = [];
    this.planEntries = [];
    this.turnActive = false;
  }
  
  resetAll(): void {
    this.workspaces = [];
    this.currentWorkspaceIndex = -1;
    this.currentSessionId = '';
    this.currentSessionTitle = '';
    this.messages = [];
    this.planEntries = [];
    this.turnActive = false;
    this.cachedModels = [];
    this.cachedModes = [];
    this.workspaceSessions = new Map();
    this.connection = {
      status: 'disconnected',
      hostName: '',
      hostUrl: ''
    };
  }
}
