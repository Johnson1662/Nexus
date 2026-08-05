import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/providers/chat_provider.dart';
import '../lib/services/host_store.dart';
import '../lib/services/storage_service.dart';
import '../lib/services/ws_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;

  setUp(() async {
    StorageService.resetForTest();
    sandbox = await Directory.systemTemp.createTemp('nexus-host-selection-');
    StorageService.sandboxForTest = sandbox.path;
  });

  tearDown(() async {
    StorageService.resetForTest();
    StorageService.sandboxForTest = null;
    if (await sandbox.exists()) await _deleteSandbox(sandbox);
  });

  test('probeBest 只探测并保留当前连接', () async {
    final aServer = await _startHost(hostId: 'host-a');
    final bServer = await _startHost(hostId: 'host-b');
    final ws = WSClient();
    final phases = <String>[];
    final disposePhase = ws.onPhaseChange((hostKey, phase, url) {
      phases.add('$hostKey:$phase:${url ?? ''}');
    });
    addTearDown(() async {
      disposePhase();
      ws.dispose();
      await aServer.close(force: true);
      await bServer.close(force: true);
    });

    final aUrl = 'ws://127.0.0.1:${aServer.port}';
    final bUrl = 'ws://127.0.0.1:${bServer.port}';
    await HttpOverrides.runZoned(() async {
      ws.connect(aUrl, 'host-a');
      await _waitUntil(() => ws.isConnected);

      final selected = await ws.probeBest([bUrl], 'host-b');

      expect(selected, bUrl);
      expect(ws.currentHostKey, 'host-a');
      expect(ws.currentUrl, aUrl);
      expect(ws.isConnected, isTrue);
      expect(phases.where((phase) => phase.startsWith('host-b:')), isEmpty);
    }, createHttpClient: _NetworkHttpOverrides().createHttpClient);
  });

  test('当前在线 Host 探测失败不改变在线状态', () async {
    final aServer = await _startHost(
      hostId: 'host-a',
      probeStatus: HttpStatus.serviceUnavailable,
    );
    final ws = WSClient();
    final provider = ChatProvider(ws);
    final hostStore = HostStore();
    addTearDown(() async {
      provider.dispose();
      ws.dispose();
      await aServer.close(force: true);
    });

    final aKey = 'host-a';
    final aUrl = 'ws://127.0.0.1:${aServer.port}';
    await HttpOverrides.runZoned(() async {
      await provider.connectToUrl(aUrl, hostKey: aKey);
      await _waitUntil(() =>
          ws.isConnected &&
          provider.state.connected &&
          hostStore.getPhase(aKey) == 'online');

      await provider.connectBest([aUrl], hostKey: aKey);

      expect(ws.isConnected, isTrue);
      expect(provider.state.connected, isTrue);
      expect(hostStore.getPhase(aKey), 'online');
    }, createHttpClient: _NetworkHttpOverrides().createHttpClient);
  });
  test('探测失败不会改变已连接 Host 的会话、游标和地址', () async {
    final aServer = await _startHost(hostId: 'host-a');
    final bServer =
        await _startHost(hostId: 'host-b', probeStatus: HttpStatus.serviceUnavailable);
    final ws = WSClient();
    final provider = ChatProvider(ws);
    final hostStore = HostStore();
    addTearDown(() async {
      provider.dispose();
      ws.dispose();
      await aServer.close(force: true);
      await bServer.close(force: true);
    });

    final aKey = 'host-a';
    final bKey = 'host-b';
    final aUrl = 'ws://127.0.0.1:${aServer.port}';
    final bUrl = 'ws://127.0.0.1:${bServer.port}';

    await HttpOverrides.runZoned(() async {
      await provider.connectToUrl(aUrl, hostKey: aKey);
      await _waitUntil(() =>
          ws.isConnected &&
          provider.state.connected &&
          hostStore.getPhase(aKey) == 'online');

      final storage = await StorageService.getInstance();
      provider.state.sessionId = 'session-a';
      provider.state.lastMessageId = 'session-a:42';
      await storage.setLastMessageId('session-a:42');
      await storage.putString('server_url', aUrl);

      await provider.connectBest([bUrl], hostKey: bKey);

      expect(provider.state.currentDeviceId, aKey);
      expect(provider.state.sessionId, 'session-a');
      expect(provider.state.lastMessageId, 'session-a:42');
      expect(storage.getString('server_url'), aUrl);
      expect(hostStore.getPhase(aKey), 'online');
      expect(hostStore.getPhase(bKey), 'offline');
      expect(provider.state.connected, isTrue);
      expect(ws.currentHostKey, aKey);
      expect(ws.isConnected, isTrue);
    }, createHttpClient: _NetworkHttpOverrides().createHttpClient);
  });

  test('较早 Host 的慢探测结果不能覆盖后发起的选择', () async {
    final aServer = await _startHost(hostId: 'host-a');
    final bServer = await _startHost(
      hostId: 'host-b',
      probeDelay: const Duration(milliseconds: 500),
    );
    final cServer = await _startHost(hostId: 'host-c');
    final ws = WSClient();
    final provider = ChatProvider(ws);
    final hostStore = HostStore();
    addTearDown(() async {
      provider.dispose();
      ws.dispose();
      await aServer.close(force: true);
      await bServer.close(force: true);
      await cServer.close(force: true);
    });

    final aKey = 'host-a';
    final bKey = 'host-b';
    final cKey = 'host-c';
    final aUrl = 'ws://127.0.0.1:${aServer.port}';
    final bUrl = 'ws://127.0.0.1:${bServer.port}';
    final cUrl = 'ws://127.0.0.1:${cServer.port}';

    await HttpOverrides.runZoned(() async {
      await provider.connectToUrl(aUrl, hostKey: aKey);
      await _waitUntil(() =>
          ws.isConnected &&
          provider.state.connected &&
          hostStore.getPhase(aKey) == 'online');

      provider.state.sessionId = 'session-a';
      provider.state.lastMessageId = 'session-a:7';
      final storage = await StorageService.getInstance();
      await storage.putString('server_url', aUrl);

      final bSelection = provider.connectBest([bUrl], hostKey: bKey);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await provider.connectBest([cUrl], hostKey: cKey);
      await _waitUntil(() =>
          ws.isConnected &&
          provider.state.connected &&
          ws.currentHostKey == cKey &&
          hostStore.getPhase(cKey) == 'online');

      final currentDeviceId = provider.state.currentDeviceId;
      final currentHostKey = ws.currentHostKey;
      final selectedUrl = storage.getString('server_url');
      final sessionId = provider.state.sessionId;
      final lastMessageId = provider.state.lastMessageId;

      await bSelection;

      expect(provider.state.currentDeviceId, currentDeviceId);
      expect(ws.currentHostKey, currentHostKey);
      expect(storage.getString('server_url'), selectedUrl);
      expect(provider.state.sessionId, sessionId);
      expect(provider.state.lastMessageId, lastMessageId);
      expect(provider.state.currentDeviceId, cKey);
      expect(storage.getString('server_url'), cUrl);
      expect(hostStore.getPhase(bKey), isNot('connecting'));
    }, createHttpClient: _NetworkHttpOverrides().createHttpClient);
  });
}

Future<HttpServer> _startHost({
  String hostId = 'host',
  int probeStatus = HttpStatus.ok,
  Duration probeDelay = Duration.zero,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/probe') {
      if (probeDelay > Duration.zero) {
        await Future<void>.delayed(probeDelay);
      }
      request.response.statusCode = probeStatus;
      await request.response.close();
      return;
    }
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      try {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.add(jsonEncode(<String, dynamic>{
          'type': 'server_info',
          'hostId': hostId,
          'hostname': hostId,
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

class _NetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
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
}Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('等待连接状态超时');
}
