import { MessageData } from '../model/MessageData';

export class MessageDataSource implements IDataSource {
  private messages: MessageData[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(messages: MessageData[]) {
    this.messages = messages;
  }

  updateData(messages: MessageData[]): void {
    this.messages = messages;
    this.notifyDataReload();
  }

  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): MessageData {
    return this.messages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    let idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notifyDataReload(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }
}
