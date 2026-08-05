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
    sandbox = await Directory.systemTemp.createTemp('nexus-host-migration-');
    StorageService.sandboxForTest = sandbox.path;
  });

  tearDown(() async {
    StorageService.resetForTest();
    StorageService.sandboxForTest = null;
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('HostStore migrates phase and active host key', () {
    final oldKey = 'legacy-host-${sandbox.path.hashCode}';
    final newKey = 'canonical-host-${sandbox.path.hashCode}';
    final store = HostStore();
    store.markConnecting(oldKey);
    store.activeHostKey = oldKey;
    store.connectedUrl = 'ws://127.0.0.1:12138';

    store.migrateHostId(oldKey, newKey);

    expect(store.getPhase(oldKey), 'unknown');
    expect(store.getPhase(newKey), 'connecting');
    expect(store.activeHostKey, newKey);
    expect(store.connectedUrl, 'ws://127.0.0.1:12138');

    store.migrateHostId('', 'another-host');
    store.markError('empty-new-boundary');
    store.migrateHostId('empty-new-boundary', '');
    expect(store.getPhase('empty-new-boundary'), 'error');
    store.migrateHostId(newKey, newKey);
    expect(store.getPhase(newKey), 'connecting');
    expect(store.activeHostKey, newKey);
  });

  test('WorkspaceProvider migrates old partition to canonical host', () async {
    const oldId = 'legacy-workspace-host';
    const newId = 'canonical-workspace-host';
    final storage = await StorageService.getInstance();
    await storage.saveWorkspaces(oldId, const ['/legacy/workspace']);
    await storage.saveWorkspaceIndex(oldId, 0);

    final provider = WorkspaceProvider();
    provider.setActiveHost(oldId);
    provider.addWorkspace('legacy', '/legacy/workspace');
    await _waitForDiskPartition(storage, sandbox, oldId);
    await provider.migrateHostId(oldId, newId);

    expect(storage.loadWorkspaces(oldId), isEmpty);
    expect(storage.getObject('workspace_index_$oldId'), isNull);
    expect(storage.loadWorkspaces(newId), ['/legacy/workspace']);
    expect(storage.loadWorkspaceIndex(newId), 0);
    expect(provider.currentWorkspace, '/legacy/workspace');
  });

  test('WorkspaceProvider keeps new partition and deletes old partition', () async {
    const oldId = 'legacy-workspace-host-existing-new';
    const newId = 'canonical-workspace-host-existing-new';
    final storage = await StorageService.getInstance();
    await storage.saveWorkspaces(oldId, const ['/legacy/workspace']);
    await storage.saveWorkspaceIndex(oldId, 1);
    await storage.saveWorkspaces(newId, const ['/canonical/workspace']);
    await storage.saveWorkspaceIndex(newId, 2);

    final provider = WorkspaceProvider();
    await provider.migrateHostId(oldId, newId);

    expect(storage.getObject('workspaces_$oldId'), isNull);
    expect(storage.getObject('workspace_index_$oldId'), isNull);
    expect(storage.loadWorkspaces(newId), ['/canonical/workspace']);
    expect(storage.loadWorkspaceIndex(newId), 2);
  });

  test('ChatProvider migrates current host and delegates workspace migration', () async {
    const oldId = 'legacy-chat-host';
    const newId = 'canonical-chat-host';
    final storage = await StorageService.getInstance();
    await storage.saveWorkspaces(oldId, const ['/chat/workspace']);
    await storage.saveWorkspaceIndex(oldId, 0);

    final workspaceProvider = WorkspaceProvider();
    workspaceProvider.setActiveHost(oldId);
    final provider = ChatProvider(
      WSClient(),
      workspaceProvider: workspaceProvider,
    );
    addTearDown(provider.dispose);
    provider.state.currentDeviceId = oldId;

    provider.migrateHostKey(oldId, newId);
    await _waitForWorkspaceMigration(storage, sandbox, oldId, newId);

    expect(provider.state.currentDeviceId, newId);
    expect(storage.getObject('workspaces_$oldId'), isNull);
    expect(storage.loadWorkspaces(newId), ['/chat/workspace']);
  });
}

Future<void> _waitForDiskPartition(
  StorageService storage,
  Directory sandbox,
  String hostId,
) async {
  final file = File('${sandbox.path}/.nexus_store.json');
  for (var attempt = 0; attempt < 100; attempt++) {
    if (storage.getObject('workspaces_$hostId') != null) {
      try {
        final disk = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (disk['workspaces_$hostId'] != null) return;
      } on Object {
        // 等待排队的原子刷盘完成。
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _waitForWorkspaceMigration(
  StorageService storage,
  Directory sandbox,
  String oldId,
  String newId,
) async {
  final file = File('${sandbox.path}/.nexus_store.json');
  for (var attempt = 0; attempt < 100; attempt++) {
    final oldRemoved =
        storage.getObject('workspaces_$oldId') == null &&
            storage.getObject('workspace_index_$oldId') == null;
    if (oldRemoved && storage.getObject('workspaces_$newId') != null) {
      try {
        final disk = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        final oldOnDisk =
            disk['workspaces_$oldId'] != null ||
                disk['workspace_index_$oldId'] != null;
        if (!oldOnDisk && disk['workspaces_$newId'] != null) return;
      } on Object {
        // 等待排队的原子刷盘完成后再删除测试沙箱。
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}