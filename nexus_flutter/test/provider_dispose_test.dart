import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/models/ws_protocol.dart';
import '../lib/providers/chat_provider.dart';
import '../lib/services/host_store.dart';
import '../lib/services/notification_service.dart';
import '../lib/services/storage_service.dart';
import '../lib/services/ws_client.dart';

ServerMessage _modelMessage(int sequence) => ServerMessage(
      type: 'model_list',
      messageId: 'session:$sequence',
      models: [
        ModelItem(modelId: 'model-$sequence', name: 'Model $sequence'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    StorageService.resetForTest();
    sandbox = await Directory.systemTemp.createTemp('nexus-provider-dispose-');
    StorageService.sandboxForTest = sandbox.path;
    NotificationService.onPermissionAction = null;
  });

  tearDown(() async {
    NotificationService.onPermissionAction = null;
    StorageService.resetForTest();
    StorageService.sandboxForTest = null;
    if (await sandbox.exists()) {
      await _deleteSandbox(sandbox);
    }
  });

  test('同一 WS 的 Provider 可独立解绑监听', () {
    final ws = WSClient();
    final provider1 = ChatProvider(ws);
    final provider2 = ChatProvider(ws);

    ws.debugDispatch(_modelMessage(1));
    expect(provider1.state.models.single.id, 'model-1');
    expect(provider2.state.models.single.id, 'model-1');

    provider1.dispose();
    ws.debugDispatch(_modelMessage(2));
    expect(provider1.state.models.single.id, 'model-1');
    expect(provider2.state.models.single.id, 'model-2');

    provider2.dispose();
    ws.dispose();
  });

  test('每条消息只通知仍存活的 Provider 一次', () {
    final ws = WSClient();
    final provider1 = ChatProvider(ws);
    final provider2 = ChatProvider(ws);
    var provider1Notifications = 0;
    var provider2Notifications = 0;
    provider1.addListener(() => provider1Notifications++);
    provider2.addListener(() => provider2Notifications++);

    ws.debugDispatch(_modelMessage(1));
    ws.debugDispatch(_modelMessage(2));
    expect(provider1Notifications, 2);
    expect(provider2Notifications, 2);

    provider1.dispose();
    ws.debugDispatch(_modelMessage(3));
    expect(provider1Notifications, 2);
    expect(provider2Notifications, 3);

    provider2.dispose();
    ws.dispose();
  });

  test('原生权限动作只进入当前 Provider', () {
    final ws = WSClient();
    final provider1 = ChatProvider(ws);
    provider1.state.pendingPermissions['request-1'] = PendingPermission(
      requestId: 'request-1',
      toolCall: 'tool-1',
      options: const [],
    );
    var provider1Notifications = 0;
    provider1.addListener(() => provider1Notifications++);

    final provider2 = ChatProvider(ws);
    provider2.state.pendingPermissions['request-2'] = PendingPermission(
      requestId: 'request-2',
      toolCall: 'tool-2',
      options: const [],
    );
    var provider2Notifications = 0;
    provider2.addListener(() => provider2Notifications++);
    final provider2Action = NotificationService.onPermissionAction;

    provider1.dispose();
    expect(NotificationService.onPermissionAction, same(provider2Action));

    NotificationService.onPermissionAction!.call('request-2', false);
    expect(provider1.state.pendingPermissions, contains('request-1'));
    expect(provider1Notifications, 0);
    expect(provider2.state.pendingPermissions, isEmpty);
    expect(provider2Notifications, 1);

    provider2.dispose();
    expect(NotificationService.onPermissionAction, isNull);
    ws.dispose();
  });

  test('探测 B 失败不影响已连接的 A', () async {
    final aServer = await _startHost(probeStatus: HttpStatus.ok);
    final bServer = await _startHost(probeStatus: HttpStatus.serviceUnavailable);
    final ws = WSClient();
    final provider = ChatProvider(ws);
    addTearDown(() async {
      provider.dispose();
      ws.dispose();
      await aServer.close(force: true);
      await bServer.close(force: true);
    });

    final aUrl = 'ws://127.0.0.1:${aServer.port}';
    final bUrl = 'ws://127.0.0.1:${bServer.port}';
    await HttpOverrides.runZoned(() async {
      await provider.connectToUrl(aUrl, hostKey: 'host-a');
      final hostStore = HostStore();
      await _waitUntil(() =>
          ws.isConnected &&
          provider.state.connected &&
          hostStore.getPhase('host-a') == 'online');

      expect(ws.currentHostKey, 'host-a');
      expect(hostStore.getPhase('host-a'), 'online');

      await provider.connectBest([bUrl], hostKey: 'host-b');

      expect(ws.currentHostKey, 'host-a');
      expect(ws.isConnected, isTrue);
      expect(provider.state.connected, isTrue);
      expect(hostStore.getPhase('host-a'), 'online');
      expect(hostStore.getPhase('host-b'), 'offline');
    }, createHttpClient: (context) => HttpClient(context: context));
  });

  test('dispose 首次调用不抛异常，解绑器可重复调用', () {
    final ws = WSClient();
    final disposers = <ListenerDisposer>[
      ws.onMessage((_) {}),
      ws.onStateChange((_, __) {}),
      ws.onServerInfo(() {}),
      ws.onAgentList((_) {}),
      ws.onError((_) {}),
      ws.onRegistryList((_) {}),
      ws.onPhaseChange((_, __, ___) {}),
    ];
    final provider = ChatProvider(ws);

    expect(() => provider.dispose(), returnsNormally);
    for (final dispose in disposers) {
      expect(() => dispose(), returnsNormally);
      expect(() => dispose(), returnsNormally);
    }

    ws.dispose();
  });
}

Future<void> _deleteSandbox(Directory sandbox) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    try {
      await sandbox.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

Future<HttpServer> _startHost({required int probeStatus}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/probe') {
      request.response.statusCode = probeStatus;
      await request.response.close();
      return;
    }
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(jsonEncode(<String, dynamic>{
          'type': 'server_info',
          'hostId': 'host-a',
          'hostname': 'host-a',
        }));
        socket.listen((_) {}, onError: (_) {});
      } catch (_) {}
      return;
    }
    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });
  return server;
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('等待连接状态超时');
}

