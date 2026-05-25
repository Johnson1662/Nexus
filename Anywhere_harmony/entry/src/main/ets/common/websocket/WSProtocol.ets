import { PlanEntry, ModelItem, ModeItem, ConfigOption, UsageInfo, AvailableCommand } from '../model/ChatState';
import { ServerSession } from '../model/WorkspaceInfo';

export interface AcpUpdate {
  sessionUpdate: string;
  content?: AcpContent;
  messageId?: string;
  toolCallId?: string;
  title?: string;
  status?: string;
  kind?: string;
  entries?: PlanEntry[];
  currentModeId?: string;
  currentValue?: string;
  configOptions?: ConfigOption[];
  availableCommands?: AvailableCommand[];
  usage?: UsageInfo;
  configId?: string;
  toolCallContent?: AcpToolCallContent[];
}

export interface AcpToolCallContent {
  type?: string;
  content?: AcpContent;
  terminalId?: string;
  path?: string;
  oldText?: string;
  newText?: string;
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
  configId?: string;
  value?: string;
  optionId?: string;
  methodId?: string;
}

export interface ServerMessage {
  type: string;
  text?: string;
  sessionId?: string;
  loadedSessionId?: string;
  agent?: string;
  model?: string;
  title?: string;
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
  configOptions?: ConfigOption[];
  hostname?: string;
  ips?: string[];
}

export interface ServerInfoMessage {
  type: string;
  hostname: string;
  ips: string[];
  hostId?: string;
  relayPin?: string;
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
