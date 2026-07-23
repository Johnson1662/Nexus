import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/device_entry.dart';

/// File-based persistence layer for OHOS Flutter.
/// Stores a single JSON file in the app's documents directory.
class StorageService {
  static const String _fileName = '.anywhere_store.json';

  static StorageService? _instance;
  Map<String, dynamic> _data = {};
  io.File? _file;
  bool _loaded = false;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      _instance = StorageService._();
      await _instance!._init();
    }
    return _instance!;
  }

  Future<void> _init() async {
    io.File file;
    // On OHOS, path_provider has no platform implementation.
    // The app sandbox base is /data/storage/el2/base/haps/entry/files/
    const sandbox = '/data/storage/el2/base/haps/entry/files';

    try {
      final dir = await getApplicationDocumentsDirectory();
      file = io.File('${dir.path}/$_fileName');
      debugPrint('[Storage] Using documents dir: ${dir.path}');
    } catch (e) {
      debugPrint('[Storage] getApplicationDocumentsDirectory failed, using sandbox dir');
      file = io.File('$sandbox/$_fileName');
    }

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
    _loaded = true;
  }

  Future<void> _flush() async {
    final file = _file;
    if (file == null) return;
    try {
      final json = jsonEncode(_data);
      await file.writeAsString(json, flush: true);
      debugPrint('[Storage] Flushed ${_data.length} keys (${json.length} bytes)');
    } catch (e) {
      debugPrint('[Storage] Write failed: $e');
    }
  }

  // ── Unified get/set ──
  String? getString(String key) => _data[key] as String?;
  Future<void> putString(String key, String value) async {
    _data[key] = value;
    await _flush();
  }

  dynamic getObject(String key) => _data[key];
  Future<void> putObject(String key, dynamic value) async {
    _data[key] = value;
    await _flush();
  }

  Future<void> remove(String key) async {
    _data.remove(key);
    await _flush();
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
    await _flush();
  }

  // ── Server URL (matches ArkTS server_url) ──
  String getServerUrlSync() => _data['server_url'] as String? ?? '';
  Future<String?> getServerUrl() async => _data['server_url'] as String?;
  Future<void> setServerUrl(String url) async {
    _data['server_url'] = url;
    await _flush();
  }

  // ── Last Agent / Model (matches ArkTS) ──
  String getLastAgentSync() => _data['last_agent'] as String? ?? '';
  String getLastModelIdSync() => _data['last_model_id'] as String? ?? '';
  Future<void> setLastAgent(String agent) async {
    _data['last_agent'] = agent;
    await _flush();
  }
  Future<void> setLastModelId(String id) async {
    _data['last_model_id'] = id;
    await _flush();
  }

  // ── Last Message ID ──
  String getLastMessageIdSync() => _data['last_message_id'] as String? ?? '';
  Future<void> setLastMessageId(String id) async {
    _data['last_message_id'] = id;
    await _flush();
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
    await _flush();
  }

  int loadWorkspaceIndex(String hostId) {
    final raw = _data['workspace_index_$hostId'];
    if (raw is int) return raw;
    return 0;
  }

  Future<void> saveWorkspaceIndex(String hostId, int index) async {
    _data['workspace_index_$hostId'] = index;
    await _flush();
  }

  // ── Device Agent Cache ──
  String? getDeviceAgentCache() => _data['device_agents_cache'] as String?;
  Future<void> setDeviceAgentCache(String raw) async {
    _data['device_agents_cache'] = raw;
    await _flush();
  }
}
