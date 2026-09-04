import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kEnabledKey = 'app_lock_enabled';
const _kPinHashKey = 'app_lock_pin_hash';
const _kSaltKey = 'app_lock_salt';
const _kBiometricKey = 'app_lock_biometric_enabled';

/// PIN-lock preferences, stored in this device's local storage only - never
/// synced anywhere - so each device has its own lock/PIN.
class AppLockService {
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricKey) ?? false;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricKey, enabled);
  }

  /// Sets a new PIN and turns the lock on.
  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    await prefs.setString(_kSaltKey, salt);
    await prefs.setString(_kPinHashKey, _hash(pin, salt));
    await prefs.setBool(_kEnabledKey, true);
  }

  Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_kSaltKey);
    final storedHash = prefs.getString(_kPinHashKey);
    if (salt == null || storedHash == null) return false;
    return _hash(pin, salt) == storedHash;
  }

  /// Turns the lock off entirely (caller must verify the current PIN first).
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, false);
    await prefs.setBool(_kBiometricKey, false);
  }

  String _generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) {
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }
}
