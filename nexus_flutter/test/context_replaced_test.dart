import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/models/message_data.dart';
import '../lib/models/ws_protocol.dart';
import '../lib/providers/chat_provider.dart';
import '../lib/services/ws_client.dart';

const _contextReplacedNotice =
    'Agent 上下文已重新创建。此前消息仍可查看，但新任务不会继承旧 Agent 上下文。';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('matching session_context_replaced only sets the persistent notice', () {
    final provider = ChatProvider(WSClient());
    addTearDown(provider.dispose);

    provider.state.sessionId = 'session-1';
    provider.state.turnActive = true;
    provider.state.errorMessage = 'existing error';
    final messages = <MessageData>[
      MessageData(role: 'user', content: '保留这条消息', id: 'message-1'),
    ];
    provider.state.messages = messages;

    provider.receiveServerMessage(ServerMessage.fromJson({
      'type': 'session_context_replaced',
      'sessionId': 'session-1',
      'reason': 'reload_failed',
      'previousAgentSessionId': 'agent-old',
      'newAgentSessionId': 'agent-new',
    }));

    expect(provider.state.contextReplacedNotice, _contextReplacedNotice);
    expect(provider.state.turnActive, isTrue);
    expect(provider.state.errorMessage, 'existing error');
    expect(provider.state.messages, same(messages));
  });

  test('mismatched session_context_replaced does not change the notice', () {
    final provider = ChatProvider(WSClient());
    addTearDown(provider.dispose);

    provider.state.sessionId = 'session-1';
    provider.state.contextReplacedNotice = '已有提示';

    provider.receiveServerMessage(ServerMessage.fromJson({
      'type': 'session_context_replaced',
      'sessionId': 'session-2',
      'reason': 'reload_failed',
    }));

    expect(provider.state.contextReplacedNotice, '已有提示');
  });

  test('resetForNewChat clears the context replacement notice', () {
    final provider = ChatProvider(WSClient());
    addTearDown(provider.dispose);

    provider.state.contextReplacedNotice = _contextReplacedNotice;
    provider.state.resetForNewChat();

    expect(provider.state.contextReplacedNotice, isEmpty);
  });

  test('START_ALREADY_IN_PROGRESS start_failed unlocks the turn with an error', () {
    final provider = ChatProvider(WSClient());
    addTearDown(provider.dispose);

    provider.state.turnActive = true;

    provider.receiveServerMessage(ServerMessage.fromJson({
      'type': 'start_failed',
      'code': 'START_ALREADY_IN_PROGRESS',
      'text': '已有启动请求正在进行',
    }));

    expect(provider.state.turnActive, isFalse);
    expect(provider.state.errorMessage, isNotEmpty);
  });
}
