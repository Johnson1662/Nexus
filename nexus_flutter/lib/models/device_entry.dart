/// Represents a saved host/device entry for connecting to a PC Bridge Server.
class DeviceEntry {
  final String hostId;
  String name;
  List<String> urls;
  String? relayUrl;
  String? relayPin;

  DeviceEntry({
    required this.hostId,
    required this.name,
    this.urls = const [],
    this.relayUrl,
    this.relayPin,
  });

  Map<String, dynamic> toJson() => {
        'hostId': hostId,
        'name': name,
        'urls': urls,
        if (relayUrl != null) 'relayUrl': relayUrl,
        if (relayPin != null) 'relayPin': relayPin,
      };

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
    );
  }
}
