import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import '../models/device_entry.dart';

/// File-based persistence layer for OHOS Flutter.
/// Stores a single JSON file in the OHOS app sandbox.
class StorageService {
  static const String _fileName = '.nexus_store.json';
  static const String keyUseHerdrBackend = 'pref_use_herdr_backend';
  static const String keyHerdrAgentCreationMode = 'pref_herdr_agent_creation_mode';
  static String keyHostBackend(String hostId) => 'backend_$hostId';

  static Future<StorageService>? _instanceFuture;
  Map<String, dynamic> _data = {};
  io.File? _file;

  @visibleForTesting
  static String? sandboxForTest;

  @visibleForTesting
  static void resetForTest() {
    _instanceFuture = null;
  }

  StorageService._();

  static Future<StorageService> getInstance() {
    return _instanceFuture ??= _create();
  }

  static Future<StorageService> _create() async {
    final svc = StorageService._();
    await svc._init();
    return svc;
  }

  String getHerdrAgentCreationMode() {
    final val = _data[keyHerdrAgentCreationMode];
    if (val is String && (val == 'pane_split' || val == 'new_tab')) return val;
    return 'pane_split';
  }

  Future<void> setHerdrAgentCreationMode(String mode) async {
    _data[keyHerdrAgentCreationMode] = mode;
    await _enqueueFlush();
  }

  Future<void> _init() async {
    // OHOS has no path_provider implementation; use the app sandbox directly.
    final sandbox = sandboxForTest ?? '/data/storage/el2/base/haps/entry/files';
    final file = io.File('$sandbox/$_fileName');
    debugPrint('[Storage] Using OHOS sandbox: ${file.path}');

    // Ensure parent directory exists
    try {
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
    } catch (_) {}

    _file = file;

    try {
      if (await file.exists()) {
        final raw = await file.readAsString();
        _data = jsonDecode(raw) as Map<String, dynamic>? ?? {};
        debugPrint('[Storage] Loaded ${_data.length} keys from $_fileName');
      } else {
        _data = {};
        debugPrint('[Storage] No existing file at ${file.path}, starting fresh');
      }
    } catch (e) {
      debugPrint('[Storage] Read failed: $e');
      _data = {};
    }
  }

  Future<void> _flush() async {
    final file = _file;
    if (file == null) return;
    try {
      final json = jsonEncode(_data);
      // 先写临时文件再原子 rename，避免崩溃/中断导致半写文件
      final tmp = io.File('${file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(file.path);
      debugPrint('[Storage] Flushed ${_data.length} keys (${json.length} bytes)');
    } catch (e) {
      debugPrint('[Storage] Write failed: $e');
      /* not rethrown — best-effort persistence */
    }
  }

  // 写队列：串行化 flush，避免并发写乱序覆盖
  Future<void> _writeQueue = Future.value();

  Future<void> _enqueueFlush() {
    final next = _writeQueue.then((_) => _flush());
    _writeQueue = next;
    return next;
  }

  // ── Unified get/set ──
  String? getString(String key) => _data[key] as String?;
  Future<void> putString(String key, String value) async {
    _data[key] = value;
    await _enqueueFlush();
  }

  dynamic getObject(String key) => _data[key];
  Future<void> putObject(String key, dynamic value) async {
    _data[key] = value;
    await _enqueueFlush();
  }

  Future<void> remove(String key) async {
    _data.remove(key);
    await _enqueueFlush();
  }

  bool getUseHerdrBackend() {
    final val = _data[keyUseHerdrBackend];
    if (val is bool) return val;
    if (val is String) return val == 'true';
    return false;
  }

  Future<void> setUseHerdrBackend(bool value) async {
    _data[keyUseHerdrBackend] = value;
    await _enqueueFlush();
  }

  /// Move every host-keyed value from one host id to another.
  ///
  /// A probe can discover a host's canonical id and replace a provisional key;
  /// without this, the backend preference and workspace list would silently
  /// reset even though the user never changed them.
  Future<void> migrateHostScopedKeys(String oldHostId, String newHostId) async {
    if (oldHostId.isEmpty || newHostId.isEmpty || oldHostId == newHostId) return;
    final oldBackendKey = keyHostBackend(oldHostId);
    final newBackendKey = keyHostBackend(newHostId);
    final moved = _data[oldBackendKey];
    if (moved != null && _data[newBackendKey] == null) {
      _data[newBackendKey] = moved;
    }
    _data.remove(oldBackendKey);

    final oldWorkspacesKey = 'workspaces_$oldHostId';
    final newWorkspacesKey = 'workspaces_$newHostId';
    final workspaces = _data[oldWorkspacesKey];
    if (workspaces != null && _data[newWorkspacesKey] == null) {
      _data[newWorkspacesKey] = workspaces;
    }
    _data.remove(oldWorkspacesKey);

    await _enqueueFlush();
  }

  String getHostPreferredBackend(String hostId) {
    if (hostId.isEmpty) return 'native';
    final val = _data[keyHostBackend(hostId)];
    if (val is String && (val == 'herdr' || val == 'native')) return val;
    return 'native';
  }

  Future<void> setHostPreferredBackend(String hostId, String backend) async {
    if (hostId.isNotEmpty) {
      _data[keyHostBackend(hostId)] = backend;
    }
    _data[keyUseHerdrBackend] = backend == 'herdr';
    await _enqueueFlush();
  }

  // ── Devices (matches ArkTS host_list) ──
  Future<List<DeviceEntry>> loadDevices() async {
    final raw = _data['host_list'];
    if (raw == null) return [];
    try {
      final list = (raw is List ? raw : jsonDecode(raw as String)) as List<dynamic>;
      return list.map((e) => DeviceEntry.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDevices(List<DeviceEntry> devices) async {
    _data['host_list'] = devices.map((d) => d.toJson()).toList();
    await _enqueueFlush();
  }

  // ── Server URL (matches ArkTS server_url) ──
  String getServerUrlSync() => _data['server_url'] as String? ?? '';
  Future<String?> getServerUrl() async => _data['server_url'] as String?;
  Future<void> setServerUrl(String url) async {
    _data['server_url'] = url;
    await _enqueueFlush();
  }

  // ── Last Agent / Model (matches ArkTS) ──
  String getLastAgentSync() => _data['last_agent'] as String? ?? '';
  String getLastModelIdSync() => _data['last_model_id'] as String? ?? '';
  Future<void> setLastAgent(String agent) async {
    _data['last_agent'] = agent;
    await _enqueueFlush();
  }
  Future<void> setLastModelId(String id) async {
    _data['last_model_id'] = id;
    await _enqueueFlush();
  }

  // ── Last Message ID ──
  String getLastMessageIdSync() => _data['last_message_id'] as String? ?? '';
  Future<void> setLastMessageId(String id) async {
    if (id.isEmpty) {
      _data.remove('last_message_id');
    } else {
      _data['last_message_id'] = id;
    }
    await _enqueueFlush();
  }

  // ── Workspaces (matches ArkTS workspaces_<scope>) ──
  List<String> loadWorkspaces(String hostId) {
    final key = 'workspaces_$hostId';
    final raw = _data[key];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  Future<void> saveWorkspaces(String hostId, List<String> paths) async {
    _data['workspaces_$hostId'] = paths;
    await _enqueueFlush();
  }

  int loadWorkspaceIndex(String hostId) {
    final raw = _data['workspace_index_$hostId'];
    if (raw is int) return raw;
    return 0;
  }

  Future<void> saveWorkspaceIndex(String hostId, int index) async {
    _data['workspace_index_$hostId'] = index;
    await _enqueueFlush();
  }

  // ── Device Agent Cache ──
  String? getDeviceAgentCache() => _data['device_agents_cache'] as String?;
  Future<void> setDeviceAgentCache(String raw) async {
    _data['device_agents_cache'] = raw;
    await _enqueueFlush();
  }
}
