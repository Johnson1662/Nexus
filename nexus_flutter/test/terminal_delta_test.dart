import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/models/message_data.dart';
import '../lib/models/ws_protocol.dart';
import '../lib/providers/chat_provider.dart';
import '../lib/services/ws_client.dart';
import '../lib/widgets/tool_call_card.dart';

/// Server 真实协议形状：tool_call_update 事件里 terminal 增量在
/// `event.toolCallContent`（content 数组的 terminal 块，文本在
/// `block.content.text`）。协议字段名/结构不可更改，客户端解析必须兼容。
Map<String, dynamic> terminalUpdate(String text, {bool truncated = false}) => {
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
            'truncated': truncated,
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

  test('terminal truncation parses and defaults to false', () {
    final notTruncated = ServerMessage.fromJson(terminalUpdate('a')).acpUpdate!;
    final truncated =
        ServerMessage.fromJson(terminalUpdate('b', truncated: true)).acpUpdate!;

    expect(notTruncated.terminalTruncated, isFalse);
    expect(truncated.terminalTruncated, isTrue);
    expect(truncated.content, 'b');
  });

  testWidgets('ToolCallCard shows terminal truncation notice', (tester) async {
    final message = MessageData(
      role: 'assistant',
      content: 'terminal',
      type: 'tool_call',
      toolName: 'terminal',
      toolContent: 'output',
      toolContentType: 'terminal',
      toolTerminalId: 'terminal-1',
      toolTruncated: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ToolCallCard(message: message)),
      ),
    );
    expect(find.text('输出已截断，仅显示前部内容'), findsNothing);

    await tester.tap(find.text('terminal'));
    await tester.pump();

    expect(find.text('输出已截断，仅显示前部内容'), findsOneWidget);
    expect(find.text('输出已截断，仅显示前 256KB'), findsNothing);
    expect(find.text('output'), findsOneWidget);
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