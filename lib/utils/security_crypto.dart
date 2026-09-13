import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecurityCrypto {
  static const String _saltKey = "PHARMAPRO_SALT_KEY";

  /// Generates a salted SHA-256 hash of the plain PIN to prevent plain-text exposure.
  static String hashPin(String plainPin) {
    final bytes = utf8.encode(plainPin + _saltKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Verifies an input PIN against a stored salted SHA-256 hash.
  static bool verifyPin(String inputPin, String storedHash) {
    if (storedHash.isEmpty) return false;
    final inputHash = hashPin(inputPin);
    return inputHash == storedHash;
  }
}
