/// Wraps a bare IPv6 literal in brackets so it can be embedded in a URL host
/// position (`ws://[2001:db8::1]:12138`). IPv4/hostnames are returned as-is.
///
/// Handles scoped IPv6 literals (fe80::1%wlan0, [fe80::1%wlan0], fe80::1%25wlan0),
/// canonically encoding the zone separator as %25 idempotently.
String bracketedHost(String host) {
  if (host.isEmpty) return host;
  var unbracketed = host;
  if (unbracketed.startsWith('[') && unbracketed.endsWith(']')) {
    unbracketed = unbracketed.substring(1, unbracketed.length - 1);
  }
  if (!unbracketed.contains(':')) return host;
  final normalized = unbracketed.replaceAll('%25', '%').replaceAll('%', '%25');
  return '[$normalized]';
}
