import 'dart:convert';
import '../models/ws_protocol.dart';
import 'storage_service.dart';

/// Per-device agent cache — mirrors ArkTS DeviceAgentStore
class DeviceAgentStore {
  static final DeviceAgentStore _instance = DeviceAgentStore._();
  factory DeviceAgentStore() => _instance;
  DeviceAgentStore._();

  final Map<String, List<AgentInfo>> _cache = {};

  List<AgentInfo> getAgents(String hostId) => _cache[hostId] ?? [];

  void saveAgents(String hostId, List<AgentInfo> agents) {
    _cache[hostId] = agents;
    _persist();
  }

  void clearHost(String hostId) {
    _cache.remove(hostId);
    _persist();
  }

  Future<void> loadFromDisk() async {
    final storage = await StorageService.getInstance();
    final raw = storage.getDeviceAgentCache() ?? '';
    if (raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      for (final entry in map.entries) {
        final list = (entry.value as List<dynamic>)
            .map((e) => AgentInfo.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _cache[entry.key] = list;
      }
    } catch (_) {}
  }

  void _persist() async {
    final storage = await StorageService.getInstance();
    final map = <String, dynamic>{};
    for (final entry in _cache.entries) {
      map[entry.key] = entry.value.map((e) => e.toJson()).toList();
    }
    await storage.setDeviceAgentCache(jsonEncode(map));
  }
}
