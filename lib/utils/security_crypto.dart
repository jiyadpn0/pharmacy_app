import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class SecurityCrypto {
  static const String _legacySaltKey = 'PHARMAPRO_SALT_KEY';
  static const int _iterations = 120000;
  static const int _saltLength = 16;

  /// Creates a versioned PBKDF2-HMAC-SHA256 hash with a unique random salt.
  static String hashPin(String plainPin) {
    final random = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    final derivedKey = _pbkdf2(utf8.encode(plainPin), salt, _iterations, 32);
    return 'pbkdf2_sha256:$_iterations:${base64Url.encode(salt)}:${base64Url.encode(derivedKey)}';
  }

  /// Verifies new PBKDF2 hashes and the legacy fixed-salt SHA-256 format.
  static bool verifyPin(String inputPin, String storedHash) {
    if (storedHash.isEmpty) return false;
    if (!storedHash.startsWith('pbkdf2_sha256:')) {
      final legacy = sha256.convert(utf8.encode(inputPin + _legacySaltKey)).toString();
      return _constantTimeEquals(utf8.encode(legacy), utf8.encode(storedHash));
    }

    try {
      final parts = storedHash.split(':');
      if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
      final iterations = int.parse(parts[1]);
      if (iterations < 10000 || iterations > 1000000) return false;
      final salt = base64Url.decode(base64Url.normalize(parts[2]));
      final expected = base64Url.decode(base64Url.normalize(parts[3]));
      final actual = _pbkdf2(utf8.encode(inputPin), salt, iterations, expected.length);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return false;
    }
  }

  static List<int> _pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
    final hmac = Hmac(sha256, password);
    final blockCount = (length / sha256.blockSize).ceil();
    final result = <int>[];

    for (var block = 1; block <= blockCount; block++) {
      final blockInput = <int>[...salt, (block >> 24) & 0xff, (block >> 16) & 0xff, (block >> 8) & 0xff, block & 0xff];
      var u = hmac.convert(blockInput).bytes;
      final accumulator = List<int>.from(u);
      for (var iteration = 1; iteration < iterations; iteration++) {
        u = hmac.convert(u).bytes;
        for (var i = 0; i < accumulator.length; i++) {
          accumulator[i] ^= u[i];
        }
      }
      result.addAll(accumulator);
    }
    return result.sublist(0, length);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
