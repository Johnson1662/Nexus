import 'package:flutter_test/flutter_test.dart';

import '../lib/models/ws_protocol.dart';
import '../lib/providers/chat_provider.dart';
import '../lib/services/ws_client.dart';

/// Server 真实协议形状：tool_call_update 事件里 terminal 增量在
/// `event.toolCallContent`（content 数组的 terminal 块，文本在
/// `block.content.text`）。协议字段名/结构不可更改，客户端解析必须兼容。
Map<String, dynamic> terminalUpdate(String text) => {
      'type': 'agent_event',
      'sessionId': 'session-1',
      'event': {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'call-1',
        'status': 'in_progress',
        'toolCallContent': [
          {
            'type': 'terminal',
            'terminalId': 'terminal-1',
            'content': {'type': 'text', 'text': text},
          },
        ],
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('terminal deltas parse separately and append without duplication', () {
    final first = ServerMessage.fromJson(terminalUpdate('a')).acpUpdate!;
    final second = ServerMessage.fromJson(terminalUpdate('b')).acpUpdate!;

    expect(first.content, 'a');
    expect(second.content, 'b');
    expect('${first.content}${second.content}', 'ab');
  });

  test('ChatProvider appends terminal deltas to one tool card', () {
    final provider = ChatProvider(WSClient());
    addTearDown(provider.dispose);

    provider.receiveServerMessage(ServerMessage.fromJson({
      'type': 'agent_event',
      'sessionId': 'session-1',
      'event': {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'toolName': 'terminal',
        'status': 'in_progress',
      },
    }));
    provider.receiveServerMessage(
      ServerMessage.fromJson(terminalUpdate('a')),
    );
    provider.receiveServerMessage(
      ServerMessage.fromJson(terminalUpdate('b')),
    );

    expect(provider.state.messages, hasLength(1));
    expect(provider.state.messages.single.toolContent, 'ab');
    expect(provider.state.messages.single.toolContentType, 'terminal');
  });

  test('100 incremental 1KB terminal chunks append to exactly 100KB', () {
    final provider = ChatProvider(WSClient());
    addTearDown(provider.dispose);

    provider.receiveServerMessage(ServerMessage.fromJson({
      'type': 'agent_event',
      'sessionId': 'session-1',
      'event': {
        'sessionUpdate': 'tool_call',
        'toolCallId': 'call-1',
        'toolName': 'terminal',
        'status': 'in_progress',
      },
    }));
    for (var i = 0; i < 100; i++) {
      provider.receiveServerMessage(
        ServerMessage.fromJson(terminalUpdate('x' * 1024)),
      );
    }

    expect(provider.state.messages, hasLength(1));
    // 增量追加：不重复、不丢字节
    expect(provider.state.messages.single.toolContent.length, 100 * 1024);
    expect(provider.state.messages.single.toolContent, 'x' * (100 * 1024));
  });
}