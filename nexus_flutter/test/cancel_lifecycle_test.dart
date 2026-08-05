import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/models/ws_protocol.dart';
import '../lib/providers/chat_provider.dart';
import '../lib/services/ws_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'session_cancelled is ACK-only: 10s fallback timer still unlocks when turn_ended never arrives',
      (tester) async {
    final provider = ChatProvider(WSClient());
    provider.state.sessionId = 's1';
    provider.state.turnActive = true;

    provider.sendMessage('__cancel__');
    expect(provider.state.cancelling, isTrue);

    // Server ACK 取消请求（当前协议：立即回 session_cancelled），但 ACP 永不发 turn_ended。
    provider.receiveServerMessage(
      ServerMessage.fromJson({'type': 'session_cancelled', 'sessionId': 's1'}),
    );
    expect(provider.state.cancelling, isTrue,
        reason: 'ACK 不清取消状态，避免刚发 cancel 就被解锁');
    expect(provider.state.turnActive, isTrue,
        reason: 'turnActive 保持到真正结束');

    // 10s 兜底 timer 触发，强制解锁。
    await tester.pump(const Duration(seconds: 10));
    expect(provider.state.cancelling, isFalse);
    expect(provider.state.turnActive, isFalse);

    provider.dispose();
  });

  testWidgets('turn_ended(cancelled) unlocks immediately and cancels fallback timer',
      (tester) async {
    final provider = ChatProvider(WSClient());
    provider.state.sessionId = 's1';
    provider.state.turnActive = true;

    provider.sendMessage('__cancel__');
    expect(provider.state.cancelling, isTrue);

    provider.receiveServerMessage(ServerMessage.fromJson({
      'type': 'session_cancelled',
      'sessionId': 's1',
    }));
    expect(provider.state.cancelling, isTrue);
    expect(provider.state.turnActive, isTrue);

    // ACP prompt 真正结束 → turn_ended(cancelled)：立即解锁。
    provider.receiveServerMessage(ServerMessage.fromJson({
      'type': 'agent_event',
      'sessionId': 's1',
      'event': {'sessionUpdate': 'turn_ended', 'stopReason': 'cancelled'},
    }));
    expect(provider.state.cancelling, isFalse);
    expect(provider.state.turnActive, isFalse);

    // 兜底 timer 已取消：继续等待不再解锁已有状态（已解锁，无副作用断言）。
    await tester.pump(const Duration(seconds: 10));
    expect(provider.state.cancelling, isFalse);

    provider.dispose();
  });
}