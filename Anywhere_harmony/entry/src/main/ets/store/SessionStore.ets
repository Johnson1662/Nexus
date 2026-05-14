import { ModelInfo, ModeInfo } from '../services/WebSocketService';

export interface MessageData {
  id: string;
  role: string;
  content: string;
  type: string;
  version: number;
  timestamp: number;
  toolName?: string;
  toolStatus?: string;
  toolCallId?: string;
  thinkingContent?: string;
  isThinkingTemp?: boolean;
}

export interface PlanEntry {
  content: string;
  status: string;
  priority?: string;
}

export interface WorkspaceInfo {
  id: string;
  name: string;
  path: string;
}

export interface ServerSession {
  sessionId: string;
  cwd: string;
  title: string;
  updatedAt: string;
}

export class SessionStore {
  workspaces: WorkspaceInfo[] = [];
  currentWorkspaceIndex: number = -1;
  currentSessionId: string = '';
  connected: boolean = false;
  agentName: string = '';
  messages: MessageData[] = [];
  planEntries: PlanEntry[] = [];
  turnActive: boolean = false;
  model: string = '';
  modelLabel: string = 'Default';
  cachedModels: ModelInfo[] = [];
  cachedModes: ModeInfo[] = [];
  workspaceSessions: Map<string, ServerSession[]> = new Map();

  hasModelsCache(): boolean {
    return this.cachedModels.length > 0;
  }

  setModelsCache(models: ModelInfo[], modes: ModeInfo[]): void {
    this.cachedModels = models;
    this.cachedModes = modes;
  }

  getModelsCache(): ModelInfo[] {
    return this.cachedModels;
  }

  getModesCache(): ModeInfo[] {
    return this.cachedModes;
  }

  hasSessionCache(path: string): boolean {
    return this.workspaceSessions.has(path);
  }

  setSessionCache(path: string, sessions: ServerSession[]): void {
    this.workspaceSessions.set(path, sessions);
  }

  getSessionCache(path: string): ServerSession[] {
    let s: ServerSession[] | undefined = this.workspaceSessions.get(path);
    if (s === undefined) {
      return [];
    }
    return s;
  }

  getCurrentWorkspace(): WorkspaceInfo | null {
    if (this.currentWorkspaceIndex < 0 || this.currentWorkspaceIndex >= this.workspaces.length) {
      return null;
    }
    return this.workspaces[this.currentWorkspaceIndex];
  }

  addWorkspace(name: string, path: string): void {
    let ws: WorkspaceInfo = {
      id: 'ws_' + Date.now().toString(),
      name: name,
      path: path
    };
    this.workspaces.push(ws);
    this.currentWorkspaceIndex = this.workspaces.length - 1;
  }

  removeWorkspace(index: number): void {
    this.workspaces.splice(index, 1);
    if (this.currentWorkspaceIndex >= this.workspaces.length) {
      this.currentWorkspaceIndex = this.workspaces.length - 1;
    }
  }

  selectWorkspace(index: number): void {
    if (index >= 0 && index < this.workspaces.length) {
      this.currentWorkspaceIndex = index;
    }
  }

  addMessage(msg: MessageData): MessageData[] {
    this.messages.push(msg);
    return this.messages;
  }

  appendToLastAssistantText(text: string): MessageData[] {
    let msgs: MessageData[] = this.messages;
    if (msgs.length > 0) {
      let lastIndex: number = msgs.length - 1;
      let last: MessageData = msgs[lastIndex];
      if (last.role === 'assistant' && last.type === 'text' && (last.toolCallId === undefined || last.toolCallId === '')) {
        let updated: MessageData = {
          id: last.id,
          role: last.role,
          content: last.content + text,
          type: last.type,
          version: last.version + 1,
          timestamp: last.timestamp
        };
        let newArr: MessageData[] = [];
        for (let i = 0; i < msgs.length; i++) {
          if (i === lastIndex) {
            newArr.push(updated);
          } else {
            newArr.push(msgs[i]);
          }
        }
        this.messages = newArr;
        return newArr;
      }
    }

    let trimmed: string = text;
    for (let i = 0; i < trimmed.length; i++) {
      if (trimmed[i] !== '\n' && trimmed[i] !== '\r' && trimmed[i] !== ' ') {
        trimmed = trimmed.substring(i);
        break;
      }
    }
    if (trimmed.length === 0) {
      return this.messages;
    }

    let newMsg: MessageData = {
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
    let msgs: MessageData[] = this.messages;
    if (msgs.length > 0) {
      let lastIndex: number = msgs.length - 1;
      let last: MessageData = msgs[lastIndex];
      if (last.role === 'assistant' && last.type === 'thinking') {
        let updated: MessageData = {
          id: last.id,
          role: last.role,
          content: last.content + text,
          type: last.type,
          version: last.version + 1,
          timestamp: last.timestamp
        };
        let newArr: MessageData[] = [];
        for (let i = 0; i < msgs.length; i++) {
          if (i === lastIndex) {
            newArr.push(updated);
          } else {
            newArr.push(msgs[i]);
          }
        }
        this.messages = newArr;
        return newArr;
      }
    }

    let newMsg: MessageData = {
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
    let msgs: MessageData[] = this.messages;
    for (let i = 0; i < msgs.length; i++) {
      if (msgs[i].toolCallId === toolCallId) {
        let original: MessageData = msgs[i];
        let updated: MessageData = {
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
        let newArr: MessageData[] = [];
        for (let j = 0; j < msgs.length; j++) {
          if (j === i) {
            newArr.push(updated);
          } else {
            newArr.push(msgs[j]);
          }
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

  addToolCall(toolCallId: string, title: string): MessageData[] {
    let msg: MessageData = {
      id: toolCallId,
      role: 'assistant',
      content: title,
      type: 'tool_call',
      version: 0,
      timestamp: Date.now(),
      toolName: title,
      toolStatus: 'pending',
      toolCallId: toolCallId
    };
    this.messages.push(msg);
    return this.messages;
  }

  appendUserMessage(text: string): MessageData[] {
    let msg: MessageData = {
      id: 'msg_' + Date.now().toString(),
      role: 'user',
      content: text,
      type: 'text',
      version: 0,
      timestamp: Date.now()
    };
    this.messages.push(msg);
    return this.messages;
  }

  resetSession(): void {
    this.currentSessionId = '';
    this.messages = [];
    this.planEntries = [];
    this.turnActive = false;
  }

  resetAll(): void {
    this.workspaces = [];
    this.currentWorkspaceIndex = -1;
    this.currentSessionId = '';
    this.connected = false;
    this.agentName = '';
    this.messages = [];
    this.planEntries = [];
    this.turnActive = false;
    this.cachedModels = [];
    this.cachedModes = [];
    this.workspaceSessions = new Map();
  }
}
