/// Represents a saved host/device entry for connecting to a PC Bridge Server.
class DeviceEntry {
  final String hostId;
  String name;
  List<String> urls;
  String? relayUrl;
  String? relayPin;
  String? authToken;

  DeviceEntry({
    required this.hostId,
    required this.name,
    this.urls = const [],
    this.relayUrl,
    this.relayPin,
    this.authToken,
  });

  Map<String, dynamic> toJson() {
    final token = authToken?.trim();
    return {
      'hostId': hostId,
      'name': name,
      'urls': urls,
      if (relayUrl != null) 'relayUrl': relayUrl,
      if (relayPin != null) 'relayPin': relayPin,
      if (token != null && token.isNotEmpty) 'authToken': token,
    };
  }

  factory DeviceEntry.fromJson(Map<String, dynamic> json) {
    var rawHostId = json['hostId'] as String? ?? '';
    var rawName = json['name'] as String? ?? '';
    final urls = (json['urls'] as List<dynamic>?)?.map((u) => u as String).toList() ?? [];

    if (rawHostId.isEmpty) {
      if (rawName.isNotEmpty) {
        rawHostId = rawName;
      } else if (urls.isNotEmpty) {
        rawHostId = urls.first;
      } else {
        rawHostId = 'host_${DateTime.now().millisecondsSinceEpoch}';
      }
    }
    if (rawName.isEmpty) {
      rawName = rawHostId;
    }

    return DeviceEntry(
      hostId: rawHostId,
      name: rawName,
      urls: urls,
      relayUrl: json['relayUrl'] as String?,
      relayPin: json['relayPin'] as String?,
      // Accept the old aliases during migration, but always write authToken.
      authToken: _readAuthToken(json),
    );
  }

  static String? _readAuthToken(Map<String, dynamic> json) {
    for (final key in const ['authToken', 'auth_token', 'token']) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
