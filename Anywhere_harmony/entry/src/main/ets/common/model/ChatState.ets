import { MessageData } from './MessageData';

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
}

export const ChatStore: ChatStoreModel = new ChatStoreModel();
