import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class SdkCrypto {
  static const _s0 = [0x29, 0xa1, 0xfd, 0x70, 0xb7, 0x1b, 0x97, 0x5b];
  static const _s1 = [0xbf, 0xff, 0xe6, 0xca, 0xe9, 0x80, 0x73, 0xfb];
  static const _s2 = [0x9d, 0x6f, 0x48, 0x47, 0x28, 0x1b, 0x62, 0x5b];
  static const _s3 = [0x0b, 0xe6, 0x34, 0xc2, 0x31, 0x78, 0x2c, 0x4c];

  static const _x0 = 0x6E;
  static const _x1 = 0xB3;
  static const _x2 = 0x2A;
  static const _x3 = 0xF7;

  static const String _hkdfInfo = 'daakia_obs_v1';

  /// Decrypts a base64-encoded AES-256-GCM payload from the observability endpoint.
  /// Blob layout: [12 bytes IV] + [N bytes ciphertext] + [16 bytes GCM tag]
  /// Returns decrypted JSON string, or null on any failure.
  static String? decryptPayload(String base64Payload, String licenseKey) {
    try {
      final blob = base64Decode(base64Payload);
      if (blob.length < 28) return null;

      final iv         = Uint8List.fromList(blob.sublist(0, 12));
      final ciphertext = blob.sublist(12, blob.length - 16);
      final tag        = blob.sublist(blob.length - 16);

      final key = _deriveKey(licenseKey);

      final ctWithTag = Uint8List(ciphertext.length + tag.length)
        ..setRange(0, ciphertext.length, ciphertext)
        ..setRange(ciphertext.length, ciphertext.length + tag.length, tag);

      final params = AEADParameters(
        KeyParameter(key),
        128,
        iv,
        Uint8List(0),
      );

      final gcm = GCMBlockCipher(AESEngine())..init(false, params);

      final output = Uint8List(ciphertext.length);
      var offset = 0;
      offset += gcm.processBytes(ctWithTag, 0, ctWithTag.length, output, offset);
      gcm.doFinal(output, offset);

      return utf8.decode(output);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _deriveKey(String licenseKey) {
    final ikm  = Uint8List.fromList(utf8.encode(licenseKey));
    final salt = _assembleSalt();
    final info = Uint8List.fromList(ascii.encode(_hkdfInfo));

    final hkdf = HKDFKeyDerivator(SHA256Digest());
    hkdf.init(HkdfParameters(ikm, 32, salt, info));

    final key = Uint8List(32);
    hkdf.deriveKey(null, 0, key, 0);
    return key;
  }

  static Uint8List _assembleSalt() {
    return Uint8List.fromList([
      ..._s0.map((b) => b ^ _x0),
      ..._s1.map((b) => b ^ _x1),
      ..._s2.map((b) => b ^ _x2),
      ..._s3.map((b) => b ^ _x3),
    ]);
  }
}
