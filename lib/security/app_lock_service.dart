import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kEnabledKey = 'app_lock_enabled';
const _kLegacyPinHashKey = 'app_lock_pin_hash';
const _kLegacySaltKey = 'app_lock_salt';
const _kBiometricKey = 'app_lock_biometric_enabled';
const _kPinHashKey = 'app_lock_v2_pin_hash';
const _kSaltKey = 'app_lock_v2_salt';
const _kIterationsKey = 'app_lock_v2_iterations';
const _kFailedAttemptsKey = 'app_lock_failed_attempts';
const _kLockedUntilKey = 'app_lock_locked_until';
const _pbkdf2Iterations = 75000;

class PinLockedException implements Exception {
  final Duration retryAfter;
  const PinLockedException(this.retryAfter);

  @override
  String toString() => 'Try again in ${retryAfter.inSeconds} seconds.';
}

/// PIN-lock state is device-local. The verifier, salt, and retry state are
/// stored in platform secure storage; only non-secret enable/biometric flags
/// remain in SharedPreferences.
class AppLockService {
  final FlutterSecureStorage secureStorage;

  AppLockService({FlutterSecureStorage? secureStorage})
    : secureStorage = secureStorage ?? const FlutterSecureStorage();

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

  /// Sets a new PIN using PBKDF2-HMAC-SHA256 and turns the lock on.
  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _randomBytes(16);
    final hash = _pbkdf2(pin, salt, _pbkdf2Iterations);
    await secureStorage.write(key: _kSaltKey, value: base64UrlEncode(salt));
    await secureStorage.write(key: _kPinHashKey, value: base64UrlEncode(hash));
    await secureStorage.write(
      key: _kIterationsKey,
      value: '$_pbkdf2Iterations',
    );
    await _clearFailures();
    await prefs.remove(_kLegacySaltKey);
    await prefs.remove(_kLegacyPinHashKey);
    await prefs.setBool(_kEnabledKey, true);
  }

  Future<bool> verifyPin(String pin) async {
    final retryAfter = await currentLockout();
    if (retryAfter > Duration.zero) throw PinLockedException(retryAfter);

    final saltText = await secureStorage.read(key: _kSaltKey);
    final storedText = await secureStorage.read(key: _kPinHashKey);
    final iterationsText = await secureStorage.read(key: _kIterationsKey);
    if (saltText != null && storedText != null) {
      final iterations =
          int.tryParse(iterationsText ?? '') ?? _pbkdf2Iterations;
      final actual = _pbkdf2(pin, base64Url.decode(saltText), iterations);
      final ok = _constantTimeEquals(actual, base64Url.decode(storedText));
      if (ok) {
        await _clearFailures();
        return true;
      }
      await _recordFailure();
      return false;
    }

    // One-time migration for devices that already have the old SHA-256
    // verifier. It is upgraded only after the correct legacy PIN is entered.
    final prefs = await SharedPreferences.getInstance();
    final legacySalt = prefs.getString(_kLegacySaltKey);
    final legacyHash = prefs.getString(_kLegacyPinHashKey);
    if (legacySalt != null && legacyHash != null) {
      final candidate = sha256
          .convert(utf8.encode('$legacySalt:$pin'))
          .toString();
      if (_constantTimeEquals(
        utf8.encode(candidate),
        utf8.encode(legacyHash),
      )) {
        await setPin(pin);
        return true;
      }
    }
    await _recordFailure();
    return false;
  }

  Future<Duration> currentLockout() async {
    final value = await secureStorage.read(key: _kLockedUntilKey);
    final lockedUntil = DateTime.tryParse(value ?? '');
    if (lockedUntil == null) return Duration.zero;
    final remaining = lockedUntil.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      await secureStorage.delete(key: _kLockedUntilKey);
      return Duration.zero;
    }
    return remaining;
  }

  /// Turns the lock off entirely (caller must verify the current PIN first).
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      secureStorage.delete(key: _kSaltKey),
      secureStorage.delete(key: _kPinHashKey),
      secureStorage.delete(key: _kIterationsKey),
      secureStorage.delete(key: _kFailedAttemptsKey),
      secureStorage.delete(key: _kLockedUntilKey),
      prefs.remove(_kLegacySaltKey),
      prefs.remove(_kLegacyPinHashKey),
      prefs.setBool(_kEnabledKey, false),
      prefs.setBool(_kBiometricKey, false),
    ]);
  }

  Future<void> _recordFailure() async {
    final previous =
        int.tryParse(
          await secureStorage.read(key: _kFailedAttemptsKey) ?? '',
        ) ??
        0;
    final attempts = previous + 1;
    await secureStorage.write(key: _kFailedAttemptsKey, value: '$attempts');
    if (attempts < 3) return;
    final exponent = min(attempts - 3, 6);
    final seconds = min(5 * (1 << exponent), 300);
    await secureStorage.write(
      key: _kLockedUntilKey,
      value: DateTime.now()
          .toUtc()
          .add(Duration(seconds: seconds))
          .toIso8601String(),
    );
  }

  Future<void> _clearFailures() async {
    await secureStorage.delete(key: _kFailedAttemptsKey);
    await secureStorage.delete(key: _kLockedUntilKey);
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  Uint8List _pbkdf2(String pin, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    final block = Uint8List(salt.length + 4)..setAll(0, salt);
    block[block.length - 1] = 1;
    var u = Uint8List.fromList(hmac.convert(block).bytes);
    final result = Uint8List.fromList(u);
    for (var iteration = 1; iteration < iterations; iteration++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var index = 0; index < result.length; index++) {
        result[index] ^= u[index];
      }
    }
    return result;
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
