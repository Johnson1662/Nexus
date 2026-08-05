import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import '../models/device_entry.dart';

/// File-based persistence layer for OHOS Flutter.
/// Stores a single JSON file in the OHOS app sandbox.
class StorageService {
  static const String _fileName = '.nexus_store.json';

  static StorageService? _instance;
  Map<String, dynamic> _data = {};
  io.File? _file;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      _instance = StorageService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    // OHOS has no path_provider implementation; use the app sandbox directly.
    const sandbox = '/data/storage/el2/base/haps/entry/files';
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
