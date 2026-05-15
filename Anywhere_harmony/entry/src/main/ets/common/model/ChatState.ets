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
}

export const ChatStore: ChatStoreModel = new ChatStoreModel();
