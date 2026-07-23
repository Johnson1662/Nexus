import { MessageData } from '../model/MessageData';

/** LazyForEach key — include length fields so streaming content changes force UI update. */
export function messageLazyKey(msg: MessageData): string {
  return msg.id + ':' + msg.content.length + ':' + msg.toolContent.length + ':' +
    msg.toolContentType + ':' + msg.toolOldText.length + ':' + msg.toolNewText.length + ':' +
    msg.toolStatus;
}

/** Fingerprint for detecting per-row visual/state changes without full list reload. */
export function messageRenderFingerprint(msg: MessageData): string {
  return msg.id + '|' + msg.role + '|' + msg.type + '|' + msg.sendStatus + '|' +
    msg.content.length + '|' + msg.toolCallId + '|' + msg.toolStatus + '|' +
    msg.toolContent.length + '|' + msg.toolContentType + '|' + msg.toolPath + '|' +
    msg.toolOldText.length + '|' + msg.toolNewText.length + '|' + String(msg.timestamp);
}

export class MessageDataSource implements IDataSource {
  private messages: MessageData[] = [];
  private listeners: DataChangeListener[] = [];

  constructor(messages: MessageData[]) {
    this.messages = messages;
  }

  updateData(messages: MessageData[]): void {
    const prev: MessageData[] = this.messages;
    const prevLen: number = prev.length;
    const nextLen: number = messages.length;

    if (prevLen === 0 && nextLen === 0) {
      this.messages = messages;
      return;
    }

    if (prevLen === 0 || nextLen === 0 || prev[0].id !== messages[0].id) {
      this.messages = messages;
      this.notifyDataReload();
      return;
    }

    const overlap: number = Math.min(prevLen, nextLen);
    for (let i: number = 0; i < overlap; i++) {
      if (prev[i].id !== messages[i].id) {
        this.messages = messages;
        this.notifyDataReload();
        return;
      }
    }

    this.messages = messages;

    for (let i: number = 0; i < overlap; i++) {
      if (messageRenderFingerprint(prev[i]) !== messageRenderFingerprint(messages[i])) {
        this.notifyDataChange(i);
      }
    }

    if (nextLen > prevLen) {
      for (let i: number = prevLen; i < nextLen; i++) {
        this.notifyDataAdd(i);
      }
    } else if (nextLen < prevLen) {
      for (let i: number = prevLen - 1; i >= nextLen; i--) {
        this.notifyDataDelete(i);
      }
    }
  }

  totalCount(): number {
    return this.messages.length;
  }

  getData(index: number): MessageData {
    return this.messages[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  private notifyDataReload(): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  private notifyDataAdd(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataAdd(index);
    }
  }

  private notifyDataChange(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }

  private notifyDataDelete(index: number): void {
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataDelete(index);
    }
  }
}