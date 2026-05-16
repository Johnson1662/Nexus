import { PlanEntry, ModelItem, ModeItem } from '../model/ChatState';
import { ServerSession } from '../model/WorkspaceInfo';

export interface AcpUpdate {
  sessionUpdate: string;
  content?: AcpContent;
  messageId?: string;
  toolCallId?: string;
  title?: string;
  status?: string;
  entries?: PlanEntry[];
}

export interface AcpContent {
  type?: string;
  text?: string;
}

export interface ClientMessage {
  type: string;
  agent?: string;
  sessionId?: string;
  text?: string;
  cwd?: string;
  model?: string;
  modeId?: string;
  requestId?: string;
  outcome?: string;
  prompt?: string;
}

export interface ServerMessage {
  type: string;
  sessionId?: string;
  loadedSessionId?: string;
  agent?: string;
  model?: string;
  event?: AcpUpdate;
  exitCode?: number;
  models?: ModelItem[];
  modes?: ModeItem[];
  sessions?: ServerSession[];
  agents?: AgentInfo[];
  stopReason?: string;
  requestId?: string;
  toolCall?: object;
  options?: object;
}

export interface AgentInfo {
  name: string;
  title: string;
  version: string;
  source: string;
  binaryPath?: string;
  installed: boolean;
  configPath?: string;
}
