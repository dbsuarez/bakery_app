import 'dart:convert';
import 'dart:typed_data';

import 'package:bakery_app/backup/backup_service.dart';
import 'package:bakery_app/import/backup_restore_service.dart';
import 'package:bakery_app/models/sale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('backup v2 validation', () {
    test('current exporter produces a restore-compatible document', () {
      final exported = buildBackupDocument(
        exportedAt: DateTime.utc(2026, 10, 19, 12),
      );

      expect(
        () => decodeAndValidateBackupV2(_bytes(exported)),
        returnsNormally,
      );
      expect(exported.keys, containsAll(_persistedKeys));
    });

    test('exporter omits payments whose deleted parent sale is absent', () {
      final exported = buildBackupDocument(
        exportedAt: DateTime.utc(2026, 10, 19, 12),
        salePayments: [
          SalePayment(
            id: 44,
            saleId: 999,
            amount: 10,
            paymentDate: DateTime.utc(2026, 10, 19),
            updatedAt: DateTime.utc(2026, 10, 19),
          ),
        ],
      );

      expect(exported['sale_payments'], isEmpty);
      expect(
        () => decodeAndValidateBackupV2(_bytes(exported)),
        returnsNormally,
      );
    });

    test('accepts a complete backup with valid references', () {
      final backup = _validBackup();

      final result = decodeAndValidateBackupV2(_bytes(backup));

      expect(result['version'], 2);
      expect(result['sales'], hasLength(1));
      expect(result['sale_payments'], hasLength(1));
    });

    test('rejects malformed JSON', () {
      expect(
        () => decodeAndValidateBackupV2(Uint8List.fromList(utf8.encode('{'))),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'The selected file is not valid JSON.',
          ),
        ),
      );
    });

    test('rejects incomplete version 1 backups', () {
      final backup = _validBackup()..['version'] = 1;

      expect(
        () => decodeAndValidateBackupV2(_bytes(backup)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Unsupported or incomplete backup version'),
          ),
        ),
      );
    });

    test('rejects a missing persisted dataset', () {
      final backup = _validBackup()..remove('expenses');

      expect(
        () => decodeAndValidateBackupV2(_bytes(backup)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'The backup is missing the "expenses" list.',
          ),
        ),
      );
    });

    test('rejects duplicate entity ids', () {
      final backup = _validBackup();
      (backup['products'] as List).add(
        Map<String, Object>.from((backup['products'] as List).first as Map),
      );

      expect(
        () => decodeAndValidateBackupV2(_bytes(backup)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'The backup contains duplicate products ids.',
          ),
        ),
      );
    });

    test('rejects a sale whose batch is absent', () {
      final backup = _validBackup();
      ((backup['sales'] as List).first as Map)['batch_id'] = 999;

      expect(
        () => decodeAndValidateBackupV2(_bytes(backup)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'sales contains an unknown batch_id reference.',
          ),
        ),
      );
    });

    test('rejects a payment whose sale is absent', () {
      final backup = _validBackup();
      ((backup['sale_payments'] as List).first as Map)['sale_id'] = 999;

      expect(
        () => decodeAndValidateBackupV2(_bytes(backup)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'sale_payments contains an unknown sale_id reference.',
          ),
        ),
      );
    });
  });
}

const _persistedKeys = <String>[
  'products',
  'customers',
  'batches',
  'sales',
  'sale_payments',
  'customer_credits',
  'loyalty_adjustments',
  'expenses',
  'customer_favorites',
  'favorite_dismissals',
];

Uint8List _bytes(Map<String, dynamic> backup) =>
    Uint8List.fromList(utf8.encode(jsonEncode(backup)));

Map<String, dynamic> _validBackup() => {
  'version': 2,
  'exported_at': '2026-10-19T12:00:00.000Z',
  'products': [
    {'id': 1, 'remote_id': '11111111-1111-4111-8111-111111111111'},
  ],
  'customers': [
    {'id': 2, 'remote_id': '22222222-2222-4222-8222-222222222222'},
  ],
  'batches': [
    {
      'id': 3,
      'remote_id': '33333333-3333-4333-8333-333333333333',
      'product_id': 1,
    },
  ],
  'sales': [
    {
      'id': 4,
      'remote_id': '44444444-4444-4444-8444-444444444444',
      'batch_id': 3,
      'customer_id': 2,
    },
  ],
  'sale_payments': [
    {
      'id': 5,
      'remote_id': '55555555-5555-4555-8555-555555555555',
      'sale_id': 4,
    },
  ],
  'customer_credits': [
    {
      'id': 6,
      'remote_id': '66666666-6666-4666-8666-666666666666',
      'customer_id': 2,
      'sale_id': 4,
    },
  ],
  'loyalty_adjustments': [
    {
      'id': 7,
      'remote_id': '77777777-7777-4777-8777-777777777777',
      'customer_id': 2,
    },
  ],
  'expenses': [
    {'id': 8, 'remote_id': '88888888-8888-4888-8888-888888888888'},
  ],
  'customer_favorites': [
    {'customer_id': 2, 'product_id': 1},
  ],
  'favorite_dismissals': [
    {'customer_id': 2, 'batch_id': 3},
  ],
};
