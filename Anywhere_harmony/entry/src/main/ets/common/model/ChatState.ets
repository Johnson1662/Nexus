import { MessageData } from './MessageData';
import { ServerSession } from './WorkspaceInfo';

/** 滑动窗口上限 — 防止长时间对话内存膨胀 */
export const MAX_MESSAGES: number = 500;

export function trimMessages(): void {
  if (ChatStore.messages.length > MAX_MESSAGES) {
    ChatStore.messages = ChatStore.messages.slice(ChatStore.messages.length - MAX_MESSAGES);
  }
}

export interface ModelItem {
  modelId: string;
  name: string;
}

export interface ModeItem {
  value: string;
  name: string;
}

export interface ConfigOptionValue {
  value: string;
  name?: string;
}

export interface ConfigOption {
  id: string;
  name: string;
  description?: string;
  type: string;
  currentValue: string;
  options: ConfigOptionValue[];
}

export interface AvailableCommand {
  name: string;
  description: string;
  hint?: string;
}

export interface UsageInfo {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}

export interface PermissionOption {
  optionId: string;
  name: string;
  kind: string;
}

export interface PendingPermission {
  requestId: string;
  toolCall: PendingToolCall;
  options: PermissionOption[];
}

export interface PendingToolCall {
  toolCallId: string;
  title: string;
  kind: string;
}

@ObservedV2
export class PlanEntry {
  @Trace content: string = '';
  @Trace status: string = '';
  @Trace priority: string = '';
}

@ObservedV2
export class ChatStoreModel {
  @Trace messages: MessageData[] = [];
  /** 断线重连游标：最后处理的 messageId（格式 bridgeSessionId:seq） */
  lastMessageId: string = '';
  @Trace planEntries: PlanEntry[] = [];
  @Trace turnActive: boolean = false;
  /** 当前 WS 桥接会话 ID，用于 input/cancel/sync 等操作 */
  @Trace bridgeSessionId: string = '';
  /** AI Agent 的真实 ACP 会话 ID，用于 load/switch session */
  @Trace acpSessionId: string = '';
  @Trace connected: boolean = false;
  /** 当前连接设备的 hostId 或 hostname — server_info 设置，断开清空 */
  @Trace currentDeviceId: string = '';
  @Trace sessions: ServerSession[] = [];
  @Trace models: ModelItem[] = [];
  @Trace modes: ModeItem[] = [];
  @Trace selectedAgentName: string = '';
  @Trace agentType: string = '';
  @Trace modelIndex: number = 0;
  @Trace modeIndex: number = 0;
  @Trace sessionCurrentModelId: string = '';
  @Trace loadingSession: boolean = false;
  @Trace sessionTitle: string = '';
  @Trace configOptions: ConfigOption[] = [];
  @Trace availableCommands: AvailableCommand[] = [];
  @Trace lastUsage: UsageInfo | null = null;
  @Trace pendingPermission: PendingPermission | null = null;
  @Trace streamingThinking: string = '';
  @Trace streamingText: string = '';
  @Trace lastModelId: string = '';
  /** 断线重连阶段：'' | 'disconnected' | 'reconnecting' | 'syncing' */
  @Trace reconnectPhase: string = '';
  /** 重连尝试次数 */
  @Trace reconnectAttempt: number = 0;
  /** 模型列表请求正在进行（list_models 请求已发出，响应未到） */
  @Trace loadingModels: boolean = false;
}

export const ChatStore: ChatStoreModel = new ChatStoreModel();
