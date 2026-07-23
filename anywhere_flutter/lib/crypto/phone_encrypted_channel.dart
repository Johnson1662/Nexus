import 'dart:typed_data';
import 'dart:convert';
import 'crypto_helper.dart';

/// AES-256-GCM frame encrypted channel — mirrors ArkTS PhoneEncryptedChannel
class PhoneEncryptedChannel {
  final Uint8List _aesKey;
  int _seq = 0;

  PhoneEncryptedChannel(this._aesKey);

  Uint8List encrypt(Uint8List plaintext) {
    final iv = Uint8List(12);
    final seq = _seq++;
    final seqBytes = _int64ToBytes(seq);

    final ciphertext = CryptoHelper.aesGcmEncrypt(_aesKey, iv, plaintext);
    // Frame: [12B IV][8B seq][ciphertext+tag]
    final frame = Uint8List(12 + 8 + ciphertext.length);
    frame.setAll(0, iv);
    frame.setAll(12, seqBytes);
    frame.setAll(20, ciphertext);
    return frame;
  }

  Uint8List decrypt(Uint8List frame) {
    if (frame.length < 20) throw FormatException('Frame too short');
    final iv = Uint8List.sublistView(frame, 0, 12);
    final ciphertext = Uint8List.sublistView(frame, 20);
    return CryptoHelper.aesGcmDecrypt(_aesKey, iv, ciphertext);
  }

  void dispose() {
    _seq = 0;
  }

  static Uint8List _int64ToBytes(int n) {
    final b = Uint8List(8);
    for (int i = 7; i >= 0; i--) {
      b[i] = n & 0xff;
      n >>= 8;
    }
    return b;
  }
}
