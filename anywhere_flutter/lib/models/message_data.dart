/// Represents a single message in a chat session.
class MessageData {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  String content;
  final String type; // 'text' | 'tool_call' | 'thinking'
  String sendStatus; // '' | 'sending' | 'sent' | 'failed'
  String toolName;
  String toolStatus; // '' | 'running' | 'completed' | 'error'
  String toolCallId;
  String toolKind;
  String toolContent;
  String toolContentType;
  String toolPath;
  String toolOldText;
  String toolNewText;
  String toolTerminalId;
  int timestamp;

  static int _counter = 0;

  MessageData({
    required this.role,
    required this.content,
    this.type = 'text',
    String? id,
    this.sendStatus = '',
    this.toolName = '',
    this.toolStatus = '',
    this.toolCallId = '',
    this.toolKind = '',
    this.toolContent = '',
    this.toolContentType = '',
    this.toolPath = '',
    this.toolOldText = '',
    this.toolNewText = '',
    this.toolTerminalId = '',
    int? timestamp,
  })  : id = (id != null && id.isNotEmpty)
            ? id
            : 'msg_${DateTime.now().millisecondsSinceEpoch}_${_counter++}',
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch {
    if (this.sendStatus.isEmpty && role == 'user') {
      this.sendStatus = 'sending';
    }
  }
}
