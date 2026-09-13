import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_flutter/models/ws_protocol.dart';
import 'package:nexus_flutter/providers/chat_provider.dart';
import 'package:nexus_flutter/services/storage_service.dart';
import 'package:nexus_flutter/services/ws_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nexus_storage_test_');
    StorageService.sandboxForTest = tempDir.path;
    StorageService.resetForTest();
  });

  tearDown(() async {
    StorageService.sandboxForTest = null;
    StorageService.resetForTest();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('StorageService persists backend preference per host', () async {
    final storage = await StorageService.getInstance();

    // Default is native
    expect(storage.getHostPreferredBackend('host-1'), 'native');
    expect(storage.getHostPreferredBackend('host-2'), 'native');

    // Set host-1 to herdr
    await storage.setHostPreferredBackend('host-1', 'herdr');
    expect(storage.getHostPreferredBackend('host-1'), 'herdr');
    expect(storage.getHostPreferredBackend('host-2'), 'native');

    // Set host-2 to native
    await storage.setHostPreferredBackend('host-2', 'native');
    expect(storage.getHostPreferredBackend('host-1'), 'herdr');
    expect(storage.getHostPreferredBackend('host-2'), 'native');
  });

  test('ChatProvider resolves effectiveBackend based on Herdr capability', () async {
    final ws = WSClient();
    final provider = ChatProvider(ws);
    await provider.initFromDisk();

    // User chooses Herdr
    await provider.setUseHerdrBackend(true);
    expect(provider.preferredBackend, 'herdr');
    // Capabilities not yet known → honour the preference rather than silently
    // switching the user back to Native ACP.
    expect(provider.effectiveBackend, 'herdr');
    expect(provider.useHerdrBackend, true);

    // Receive capabilities with Herdr available = true
    provider.handleMessageForTest(ServerMessage(
      type: 'host_capabilities',
      hostCapabilities: const HostCapabilities(
        platform: 'linux',
        arch: 'x64',
        git: GitCapability(available: true),
        herdr: HerdrCapability(available: true),
        agents: [],
      ),
    ));

    expect(provider.effectiveBackend, 'herdr');
    expect(provider.useHerdrBackend, true);

    // Receive capabilities with Herdr available = false (daemon stopped)
    provider.handleMessageForTest(ServerMessage(
      type: 'host_capabilities',
      hostCapabilities: const HostCapabilities(
        platform: 'linux',
        arch: 'x64',
        git: GitCapability(available: true),
        herdr: HerdrCapability(available: false),
        agents: [],
      ),
    ));

    // Preferred is still herdr, but effective degrades to native!
    expect(provider.preferredBackend, 'herdr');
    expect(provider.effectiveBackend, 'native');
    expect(provider.useHerdrBackend, false);
  });
}
