import { MessageData } from './MessageData';
import { ServerSession } from './WorkspaceInfo';

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

@ObservedV2
export class PlanEntry {
  @Trace content: string = '';
  @Trace status: string = '';
  @Trace priority: string = '';
}

@ObservedV2
export class ChatStoreModel {
  @Trace messages: MessageData[] = [];
  @Trace planEntries: PlanEntry[] = [];
  @Trace turnActive: boolean = false;
  @Trace sessionId: string = '';
  @Trace loadedSessionId: string = '';
  @Trace connected: boolean = false;
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
}

export const ChatStore: ChatStoreModel = new ChatStoreModel();
