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
  // ── 消息 ──
  @Trace messages: MessageData[] = [];
  lastMessageId: string = '';
  @Trace planEntries: PlanEntry[] = [];

  // ── Turn / 流式 ──
  @Trace turnActive: boolean = false;
  /** 聊天页面是否在前台可见，hidden freeze 使用 */
  @Trace chatPageActive: boolean = true;
  @Trace streamingThinking: string = '';
  @Trace streamingText: string = '';

  // ── 连接 ──
  @Trace connected: boolean = false;
  /** 当前连接设备的 hostId 或 hostname — server_info 设置，断开清空 */
  @Trace currentDeviceId: string = '';
  /** 当前 WS 桥接会话 ID，用于 input/cancel/sync 等操作 */
  @Trace bridgeSessionId: string = '';
  /** AI Agent 的真实 ACP 会话 ID，用于 load/switch session */
  @Trace acpSessionId: string = '';
  /** 断线重连阶段：'' | 'disconnected' | 'reconnecting' | 'syncing' */
  @Trace reconnectPhase: string = '';
  /** 重连尝试次数 */
  @Trace reconnectAttempt: number = 0;

  // ── 会话 / 标题 ──
  @Trace sessions: ServerSession[] = [];
  @Trace loadingSession: boolean = false;
  @Trace sessionTitle: string = '';
  @Trace sessionCurrentModelId: string = '';

  // ── Agent / Model / Mode ──
  @Trace selectedAgentName: string = '';
  @Trace agentType: string = '';
  @Trace models: ModelItem[] = [];
  @Trace modelIndex: number = 0;
  @Trace lastModelId: string = '';
  @Trace modes: ModeItem[] = [];
  @Trace modeIndex: number = 0;
  @Trace loadingModels: boolean = false;
  @Trace configOptions: ConfigOption[] = [];
  @Trace availableCommands: AvailableCommand[] = [];

  // ── 权限 / 用量 ──
  @Trace lastUsage: UsageInfo | null = null;
  @Trace pendingPermission: PendingPermission | null = null;
}

export const ChatStore: ChatStoreModel = new ChatStoreModel();
