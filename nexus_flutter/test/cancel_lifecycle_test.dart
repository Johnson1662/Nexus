import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_flutter/models/ws_protocol.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/ws_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cancel lifecycle handles session_cancelled, turn_ended and cancel_failed', () async {
    final ws = WSClient();
    final provider = ChatProvider(ws);

    provider.state.sessionId = 'test-session-1';
    provider.state.turnActive = true;

    // 1. Send cancel
    provider.sendMessage('__cancel__');
    expect(provider.state.cancelling, true);
    expect(provider.state.turnActive, true); // Still active until acknowledged / completed

    // 2. Server ACK session_cancelled
    provider.handleMessageForTest(ServerMessage(
      type: 'session_cancelled',
      sessionId: 'test-session-1',
      ok: true,
    ));
    expect(provider.state.cancelling, true);
    expect(provider.state.turnActive, true);

    // 3. Server sends turn_ended
    provider.handleMessageForTest(ServerMessage(
      type: 'turn_ended',
      sessionId: 'test-session-1',
    ));
    expect(provider.state.cancelling, false);
    expect(provider.state.turnActive, false); // Genuinely unlocked!

    // 4. Test cancel_failed
    provider.state.turnActive = true;
    provider.sendMessage('__cancel__');
    expect(provider.state.cancelling, true);

    provider.handleMessageForTest(ServerMessage(
      type: 'cancel_failed',
      sessionId: 'test-session-1',
      error: 'Agent did not stop after cancel signal',
    ));
    expect(provider.state.cancelling, false);
    expect(provider.state.turnActive, true); // Keeps blocked!
    expect(provider.state.errorMessage, 'Agent did not stop after cancel signal');
  });

  test('answerAsk routes directly to interact_herdr_blocked in Herdr mode', () async {
    final ws = WSClient();
    ws.connectedForTest = true;
    final provider = ChatProvider(ws);

    provider.state.sessionId = 'herdr:w1:p2';
    provider.state.turnActive = true;

    ClientMessage? sent;
    ws.onSendForTest = (msg) {
      sent = msg;
    };

    await provider.answerAsk('1');
    expect(sent, isNotNull);
    expect(sent!.type, 'interact_herdr_blocked');
    expect(sent!.paneId, 'herdr:w1:p2');
    expect(sent!.key, '1');
  });
}
