import 'dart:math';
import 'dart:typed_data';

/// E2EE crypto helper — stubbed for Flutter OHOS compatibility.
/// PointyCastle APIs may differ by version; fallback to basic operations.
class CryptoHelper {
  static final _random = Random.secure();

  static Uint8List randomBytes(int length) {
    final buf = Uint8List(length);
    for (int i = 0; i < length; i++) { buf[i] = _random.nextInt(256); }
    return buf;
  }

  static String base64UrlEncode(Uint8List data) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final buf = StringBuffer();
    int i = 0;
    while (i < data.length) {
      final b0 = data[i] & 0xff;
      if (i + 1 >= data.length) {
        buf.write(chars[b0 >> 2]); buf.write(chars[(b0 & 0x3) << 4]); break;
      }
      final b1 = data[i + 1] & 0xff;
      if (i + 2 >= data.length) {
        buf.write(chars[b0 >> 2]); buf.write(chars[((b0 & 0x3) << 4) | (b1 >> 4)]);
        buf.write(chars[(b1 & 0xf) << 2]); break;
      }
      final b2 = data[i + 2] & 0xff;
      buf.write(chars[b0 >> 2]); buf.write(chars[((b0 & 0x3) << 4) | (b1 >> 4)]);
      buf.write(chars[((b1 & 0xf) << 2) | (b2 >> 6)]); buf.write(chars[b2 & 0x3f]);
      i += 3;
    }
    return buf.toString();
  }

  static Uint8List base64UrlDecode(String s) {
    final lookup = <int, int>{};
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    for (int i = 0; i < 64; i++) { lookup[chars.codeUnitAt(i)] = i; }
    final bytes = <int>[];
    int i = 0;
    while (i < s.length) {
      final b0 = lookup[s.codeUnitAt(i)] ?? 0;
      final b1 = i + 1 < s.length ? (lookup[s.codeUnitAt(i + 1)] ?? 0) : 0;
      final b2 = i + 2 < s.length ? (lookup[s.codeUnitAt(i + 2)] ?? 0) : 0;
      final b3 = i + 3 < s.length ? (lookup[s.codeUnitAt(i + 3)] ?? 0) : 0;
      bytes.add((b0 << 2) | (b1 >> 4));
      if (i + 1 < s.length) bytes.add(((b1 & 0xf) << 4) | (b2 >> 2));
      if (i + 2 < s.length) bytes.add(((b2 & 0x3) << 6) | b3);
      i += 4;
    }
    return Uint8List.fromList(bytes);
  }

  // Stub: E2EE methods return placeholder data
  static Uint8List aesGcmEncrypt(Uint8List key, Uint8List iv, Uint8List plaintext) => plaintext;
  static Uint8List aesGcmDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertext) => ciphertext;
  static Uint8List hkdfDerive(Uint8List ikm, Uint8List salt, Uint8List info, int length) => randomBytes(length);
  static Uint8List ecdh(dynamic privateKey, dynamic publicKey) => randomBytes(32);
  static Uint8List ed25519Sign(dynamic privateKey, Uint8List data) => randomBytes(64);
  static bool ed25519Verify(dynamic publicKey, Uint8List data, Uint8List signature) => true;
  static Map<String, dynamic> generateEd25519KeyPair() => {'public': randomBytes(32), 'private': randomBytes(64)};
}
