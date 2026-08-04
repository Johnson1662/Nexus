import 'package:flutter/foundation.dart';

import '../models/device_entry.dart';
import 'storage_service.dart';

/// In-memory singleton for host/device management.
class HostStore extends ChangeNotifier {
  static final HostStore _instance = HostStore._();
  factory HostStore() => _instance;
  HostStore._();

  List<DeviceEntry> devices = [];
  String activeHostKey = '';
  String connectedUrl = '';

  // Host online status: hostKey → phase string
  final Map<String, String> _hostPhases = {};

  String getPhase(String hostKey) => _hostPhases[hostKey] ?? 'unknown';

  bool isOnline(String hostKey) => _hostPhases[hostKey] == 'online';

  bool isDeviceOnline(DeviceEntry d) {
    final key = d.hostId;
    return _hostPhases[key] == 'online';
  }

  void setPhase(String hostKey, String phase, {String? url}) {
    _hostPhases[hostKey] = phase;
    if (phase == 'online' && url != null) {
      activeHostKey = hostKey;
      connectedUrl = url;
    }
    notifyListeners();
  }

  void markOnline(String hostKey, String url) {
    setPhase(hostKey, 'online', url: url);
  }

  void markOffline(String hostKey) {
    setPhase(hostKey, 'offline');
  }

  void markReconnecting(String hostKey) {
    setPhase(hostKey, 'reconnecting');
  }

  void markConnecting(String hostKey) {
    setPhase(hostKey, 'connecting');
  }

  void markError(String hostKey) {
    setPhase(hostKey, 'error');
  }

  void addOrUpdateDevice(DeviceEntry device) {
    int existingIdx = -1;

    // 1st Priority: Match by exact hostId
    if (device.hostId.isNotEmpty) {
      existingIdx = devices.indexWhere((d) => d.hostId == device.hostId);
    }

    // 2nd Priority: Match by name (hostname)
    if (existingIdx < 0 && device.name.isNotEmpty) {
      existingIdx = devices.indexWhere(
        (d) => d.name == device.name || (d.hostId.isNotEmpty && d.hostId == device.name),
      );
    }

    // 3rd Priority: Match by candidate URL
    if (existingIdx < 0 && device.urls.isNotEmpty) {
      existingIdx = devices.indexWhere(
        (d) => d.urls.any((u) => device.urls.contains(u)),
      );
    }

    if (existingIdx >= 0) {
      final old = devices[existingIdx];
      // Merge candidate URLs (deduplicate)
      final mergedUrls = <String>[...old.urls];
      for (final url in device.urls) {
        final normalized = _normalizeUrl(url);
        if (normalized.isNotEmpty && !mergedUrls.contains(normalized)) {
          mergedUrls.add(normalized);
        }
      }

      // Update name if new name is actual hostname and old name was IP address
      final name = (device.name.isNotEmpty && !_isIp(device.name))
          ? device.name
          : (old.name.isNotEmpty ? old.name : device.name);

      // Upgrade hostId if old hostId was temporary/empty
      final hostId = (device.hostId.isNotEmpty && !device.hostId.startsWith('host_'))
          ? device.hostId
          : (old.hostId.isNotEmpty ? old.hostId : device.hostId);

      devices[existingIdx] = DeviceEntry(
        hostId: hostId,
        name: name,
        urls: mergedUrls,
        relayUrl: device.relayUrl ?? old.relayUrl,
        relayPin: device.relayPin ?? old.relayPin,
        authToken: _mergeAuthToken(device.authToken, old.authToken),
      );
    } else {
      // Normalize URLs before adding
      final normalizedUrls = device.urls.map(_normalizeUrl).where((u) => u.isNotEmpty).toList();
      devices.add(DeviceEntry(
        hostId: device.hostId,
        name: device.name,
        urls: normalizedUrls,
        relayUrl: device.relayUrl,
        relayPin: device.relayPin,
        authToken: _mergeAuthToken(device.authToken, null),
      ));
    }
    deduplicate();
    notifyListeners();
  }

  void deduplicate() {
    final merged = <DeviceEntry>[];
    for (final d in devices) {
      int existingIdx = -1;
      if (d.hostId.isNotEmpty && !d.hostId.startsWith('host_')) {
        existingIdx = merged.indexWhere((m) => m.hostId.isNotEmpty && m.hostId == d.hostId);
      }
      if (existingIdx < 0 && d.name.isNotEmpty && !_isIp(d.name)) {
        existingIdx = merged.indexWhere(
          (m) => m.name == d.name || (m.hostId.isNotEmpty && m.hostId == d.name),
        );
      }
      if (existingIdx < 0 && d.urls.isNotEmpty) {
        existingIdx = merged.indexWhere(
          (m) => m.urls.any((u) => d.urls.contains(u)),
        );
      }

      if (existingIdx >= 0) {
        final old = merged[existingIdx];
        final mergedUrls = <String>[...old.urls];
        for (final url in d.urls) {
          final normalized = _normalizeUrl(url);
          if (normalized.isNotEmpty && !mergedUrls.contains(normalized)) {
            mergedUrls.add(normalized);
          }
        }
        final name = (d.name.isNotEmpty && !_isIp(d.name))
            ? d.name
            : (old.name.isNotEmpty ? old.name : d.name);
        final hostId = (d.hostId.isNotEmpty && !d.hostId.startsWith('host_'))
            ? d.hostId
            : (old.hostId.isNotEmpty ? old.hostId : d.hostId);

        merged[existingIdx] = DeviceEntry(
          hostId: hostId,
          name: name,
          urls: mergedUrls,
          relayUrl: d.relayUrl ?? old.relayUrl,
          relayPin: d.relayPin ?? old.relayPin,
          authToken: _mergeAuthToken(d.authToken, old.authToken),
        );
      } else {
        merged.add(d);
      }
    }
    devices = merged;
  }

  String? _mergeAuthToken(String? preferred, String? fallback) {
    final token = preferred?.trim();
    if (token != null && token.isNotEmpty) return token;
    final oldToken = fallback?.trim();
    return oldToken == null || oldToken.isEmpty ? null : oldToken;
  }

  String _normalizeUrl(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  bool _isIp(String str) {
    return RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(str);
  }

  void removeDevice(int index) {
    if (index >= 0 && index < devices.length) {
      _hostPhases.remove(devices[index].hostId);
      devices.removeAt(index);
      notifyListeners();
    }
  }

  Future<void> loadFromDisk() async {
    final storage = await StorageService.getInstance();
    devices = await storage.loadDevices();
    deduplicate();
    notifyListeners();
  }

  Future<void> saveToDisk() async {
    final storage = await StorageService.getInstance();
    await storage.saveDevices(devices);
  }
}
