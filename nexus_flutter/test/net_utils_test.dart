import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_flutter/utils/net_utils.dart';

void main() {
  test('bracketedHost wraps only bare IPv6 literals', () {
    expect(bracketedHost('192.168.1.10'), '192.168.1.10');
    expect(bracketedHost('my-laptop.local'), 'my-laptop.local');
    expect(bracketedHost('2001:db8::1'), '[2001:db8::1]');
    expect(bracketedHost('fd00::5'), '[fd00::5]');
    expect(bracketedHost('[2001:db8::1]'), '[2001:db8::1]');
    expect(bracketedHost(''), '');
  });

  test('bracketed IPv6 host produces a legal WebSocket URL', () {
    final url = 'ws://${bracketedHost('fd7a:115c:a1e0::1')}:12138';
    expect(url, 'ws://[fd7a:115c:a1e0::1]:12138');
    expect(Uri.parse(url).port, 12138);
    expect(Uri.parse(url).host, 'fd7a:115c:a1e0::1');
  });
}
