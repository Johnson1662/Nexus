/// Wraps a bare IPv6 literal in brackets so it can be embedded in a URL host
/// position (`ws://[2001:db8::1]:12138`). IPv4/hostnames are returned as-is.
String bracketedHost(String host) {
  if (host.isEmpty || host.startsWith('[')) return host;
  return host.contains(':') ? '[$host]' : host;
}
