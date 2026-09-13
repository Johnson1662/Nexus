import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_flutter/models/ws_protocol.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/ws_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('createHerdrWorkspace sends protocol message and handles failure', () async {
    final ws = WSClient();
    final provider = ChatProvider(ws);

    ClientMessage? sent;
    ws.onSendForTest = (msg) {
      sent = msg;
    };

    provider.createHerdrWorkspace(label: 'my-workspace', cwd: '/projects/my-workspace');
    expect(sent, isNotNull);
    expect(sent!.type, 'create_herdr_workspace');
    expect(sent!.label, 'my-workspace');
    expect(sent!.cwd, '/projects/my-workspace');

    // Simulate failure response from Bridge
    provider.handleMessageForTest(ServerMessage(
      type: 'create_herdr_workspace_done',
      ok: false,
      error: 'HERDR_WORKSPACE_CREATE_FAILED',
    ));

    expect(provider.state.errorMessage, 'HERDR_WORKSPACE_CREATE_FAILED');
  });
}
