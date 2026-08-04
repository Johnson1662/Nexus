import 'package:flutter_test/flutter_test.dart';

import '../lib/models/device_entry.dart';
import '../lib/models/ws_protocol.dart';
import '../lib/providers/chat_provider.dart';
import '../lib/services/host_store.dart';
import '../lib/services/ws_client.dart';

class _FakeWSClient extends WSClient {
  final List<ClientMessage> sent = [];
  final List<MessageCallback> messageListeners = [];

  @override
  bool get isConnected => true;

  @override
  String get currentHostKey => 'bridge';

  @override
  String get currentUrl => 'ws://bridge';

  @override
  void onMessage(MessageCallback callback) => messageListeners.add(callback);

  @override
  void send(ClientMessage message) => sent.add(message);

  void emit(ServerMessage message) {
    for (final listener in List<MessageCallback>.from(messageListeners)) {
      listener(message);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DeviceEntry migrates token aliases and writes authToken', () {
    final device = DeviceEntry.fromJson({
      'hostId': 'bridge',
      'name': 'Bridge',
      'urls': ['ws://bridge'],
      'token': ' legacy-token ',
    });

    expect(device.authToken, 'legacy-token');
    expect(device.toJson()['authToken'], 'legacy-token');
    expect(device.toJson().containsKey('token'), isFalse);
  });

  test('HostStore merge keeps an existing token when discovery omits it', () {
    final store = HostStore();
    store.devices = [
      DeviceEntry(
        hostId: 'bridge',
        name: 'Bridge',
        urls: ['ws://bridge'],
        authToken: 'saved-token',
      ),
    ];

    store.addOrUpdateDevice(
      DeviceEntry(hostId: 'bridge', name: 'Bridge', urls: ['ws://bridge/']),
    );

    expect(store.devices.single.authToken, 'saved-token');
  });

  test('duplicate start is rejected while a turn is in flight', () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);

    provider.sendMessage('first');
    provider.sendMessage('duplicate');

    expect(ws.sent.where((m) => m.type == 'start'), hasLength(1));
    expect(provider.state.messages, hasLength(1));
    expect(provider.state.errorMessage, contains('正在运行'));
  });

  test('server cursor deduplicates replayed agent events', () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessionId = 'session';
    provider.state.turnActive = true;

    final event = AcpUpdate(event: 'agent_message_chunk', text: 'hello');
    final message = ServerMessage(
      type: 'agent_event',
      sessionId: 'session',
      messageId: 'session:1',
      event: event,
    );
    ws.emit(message);
    ws.emit(message);

    expect(provider.state.messages, hasLength(1));
    expect(provider.state.messages.single.content, 'hello');
    expect(provider.state.lastMessageId, 'session:1');
  });

  test('sync overflow clears turn state and reloads the session', () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessionId = 'session';
    provider.state.turnActive = true;

    ws.emit(ServerMessage(
      type: 'sync_response',
      sessionId: 'session',
      overflow: true,
    ));

    expect(provider.state.turnActive, isFalse);
    expect(ws.sent.any((m) => m.type == 'load_session'), isTrue);
  });

  test('authenticated server_info automatically requests cursor sync', () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessionId = 'session';
    provider.state.lastMessageId = 'session:4';

    ws.emit(ServerMessage(type: 'server_info', hostId: 'bridge'));

    expect(
      ws.sent.any((m) =>
          m.type == 'sync_request' &&
          m.sessionId == 'session' &&
          m.lastMessageId == 'session:4'),
      isTrue,
    );
  });

}
