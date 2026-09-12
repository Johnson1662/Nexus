import 'package:flutter_test/flutter_test.dart';

import '../lib/models/device_entry.dart';
import '../lib/models/message_data.dart';
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
  ListenerDisposer onMessage(MessageCallback callback) {
    messageListeners.add(callback);
    return () => messageListeners.remove(callback);
  }

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

  test('Herdr mode without a pane never starts a Native ACP session', () async {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    await provider.setUseHerdrBackend(true);
    ws.sent.clear();

    provider.sendMessage('hello');

    expect(ws.sent.where((message) => message.type == 'start'), isEmpty);
    expect(provider.state.errorMessage, contains('Herdr'));
  });

  test('Herdr close waits for server confirmation before removing the session', () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessions = [
      ServerSessionData(sessionId: 'herdr:pane', title: 'Pane'),
    ];

    provider.closeSession('herdr:pane');
    expect(provider.state.sessions, hasLength(1));

    ws.emit(ServerMessage(type: 'session_closed', sessionId: 'herdr:pane'));
    expect(provider.state.sessions, isEmpty);
  });

  test('创建 Herdr Agent 会先清空旧会话状态', () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessionId = 'herdr:old-pane';
    provider.state.messages = [
      MessageData(role: 'assistant', content: '旧会话'),
    ];

    provider.createHerdrAgent(workspaceId: 'workspace-1', agentKind: 'omp');

    expect(provider.state.sessionId, isEmpty);
    expect(provider.state.messages, isEmpty);
    expect(ws.sent.single.type, 'create_herdr_agent');

    ws.emit(ServerMessage.fromJson({
      'type': 'create_herdr_agent_done',
      'sessionId': 'herdr:new-pane',
      'agent': 'omp',
      'freshAt': 123,
    }));
    expect(provider.state.sessionId, 'herdr:new-pane');
    expect(provider.state.messages, isEmpty);
    expect(ws.sent.last.type, 'load_session');
    expect(ws.sent.last.freshAt, 123);

    ws.emit(ServerMessage.fromJson({
      'type': 'session_started',
      'sessionId': 'herdr:old-pane',
      'resumed': true,
    }));
    expect(provider.state.sessionId, 'herdr:new-pane');
    expect(provider.state.messages, isEmpty);
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

  test(
      'late cursor event cannot advance state after the current session closes',
      () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessionId = 'session-a';
    provider.state.lastMessageId = 'session-a:4';
    provider.state.sessionId = '';
    provider.state.lastMessageId = '';

    ws.emit(ServerMessage(
      type: 'agent_event',
      sessionId: 'session-b',
      messageId: 'session-b:42',
      event: AcpUpdate(event: 'agent_message_chunk', text: 'late'),
    ));

    expect(provider.state.messages, isEmpty);
    expect(provider.state.lastMessageId, isEmpty);
  });

  test('late event from a closed session cannot repopulate the empty chat', () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessionId = 'session-a';
    provider.state.sessionId = '';

    ws.emit(ServerMessage(
      type: 'agent_event',
      sessionId: 'session-a',
      event: AcpUpdate(event: 'agent_message_chunk', text: 'late'),
    ));

    expect(provider.state.messages, isEmpty);
  });

  test(
      'session-scoped legacy event without a session id cannot pollute the chat',
      () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessionId = '';

    ws.emit(ServerMessage(
      type: 'agent_event',
      event: AcpUpdate(event: 'agent_message_chunk', text: 'unscoped'),
    ));

    expect(provider.state.messages, isEmpty);
  });

  test('delayed sync response from session A cannot mutate session B', () {
    final ws = _FakeWSClient();
    final provider = ChatProvider(ws);
    addTearDown(provider.dispose);
    provider.state.sessionId = 'session-a';
    provider.state.lastMessageId = 'session-a:4';
    provider.syncRequest();

    provider.state.sessionId = 'session-b';
    provider.state.turnActive = true;
    provider.state.lastMessageId = 'session-b:2';
    provider.state.messages = [
      MessageData(role: 'assistant', content: 'B is still here'),
    ];

    ws.emit(ServerMessage.fromJson({
      'type': 'sync_response',
      'sessionId': 'session-a',
      'turnActive': false,
      'entries': [
        {
          'messageId': 'session-a:5',
          'payload': {
            'type': 'agent_event',
            'sessionId': 'session-a',
            'messageId': 'session-a:5',
            'event': {
              'sessionUpdate': 'agent_message_chunk',
              'content': 'late A',
            },
          },
        },
      ],
    }));

    expect(provider.state.turnActive, isTrue);
    expect(provider.state.lastMessageId, 'session-b:2');
    expect(provider.state.messages.single.content, 'B is still here');
  });

  test('binary WS frames are rejected without a String cast', () {
    final ws = WSClient();
    addTearDown(ws.dispose);
    final errors = <String>[];
    ws.onError(errors.add);

    ws.handleIncomingDataForTest(<int>[123, 125]);

    expect(errors, contains('收到不支持的二进制帧'));
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
