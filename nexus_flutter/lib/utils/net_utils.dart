/// Wraps a bare IPv6 literal in brackets so it can be embedded in a URL host
/// position (`ws://[2001:db8::1]:12138`). IPv4/hostnames are returned as-is.
String bracketedHost(String host) {
  if (host.isEmpty || host.startsWith('[')) return host;
  // A scoped IPv6 literal (fe80::1%wlan0) is only valid in a URL when the zone
  // separator is percent-encoded as %25.
  final encoded = host.replaceAll('%', '%25');
  return encoded.contains(':') ? '[$encoded]' : encoded;
}
