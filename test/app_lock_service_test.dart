import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bakery_app/security/app_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('new PIN is verified from secure storage', () async {
    final service = AppLockService();
    await service.setPin('1234');

    expect(await service.isEnabled(), isTrue);
    expect(await service.verifyPin('1234'), isTrue);
    expect(await service.verifyPin('9999'), isFalse);
  });

  test('legacy verifier migrates after successful verification', () async {
    const salt = 'legacy-salt';
    final hash = sha256.convert(utf8.encode('$salt:2468')).toString();
    SharedPreferences.setMockInitialValues({
      'app_lock_enabled': true,
      'app_lock_salt': salt,
      'app_lock_pin_hash': hash,
    });
    final service = AppLockService();

    expect(await service.verifyPin('2468'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_lock_pin_hash'), isNull);
    expect(await service.verifyPin('2468'), isTrue);
  });

  test('third failed attempt creates a persistent lockout', () async {
    final service = AppLockService();
    await service.setPin('1357');

    expect(await service.verifyPin('0000'), isFalse);
    expect(await service.verifyPin('0000'), isFalse);
    expect(await service.verifyPin('0000'), isFalse);
    expect(await service.currentLockout(), greaterThan(Duration.zero));
    await expectLater(
      service.verifyPin('1357'),
      throwsA(isA<PinLockedException>()),
    );
  });
}
