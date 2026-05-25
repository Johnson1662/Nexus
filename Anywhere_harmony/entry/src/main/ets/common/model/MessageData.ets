@ObservedV2
export class MessageData {
  @Trace id: string = '';
  @Trace role: string = '';
  @Trace content: string = '';
  @Trace type: string = 'text';
  @Trace toolName: string = '';
  @Trace toolStatus: string = '';
  @Trace toolCallId: string = '';
  @Trace toolKind: string = '';
  @Trace toolContent: string = '';
  @Trace toolContentType: string = '';
  @Trace toolPath: string = '';
  @Trace toolOldText: string = '';
  @Trace toolNewText: string = '';
  @Trace toolTerminalId: string = '';
  @Trace timestamp: number = 0;

  constructor(role: string, content: string, type: string = 'text') {
    this.id = 'msg_' + Date.now().toString();
    this.role = role;
    this.content = content;
    this.type = type;
    this.timestamp = Date.now();
  }
}
