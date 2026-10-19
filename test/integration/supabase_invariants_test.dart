import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

final _run =
    const bool.fromEnvironment('RUN_SUPABASE_INTEGRATION_TESTS') ||
    Platform.environment['RUN_SUPABASE_INTEGRATION_TESTS'] == 'true';
final _url = const String.fromEnvironment('SUPABASE_TEST_URL').isNotEmpty
    ? const String.fromEnvironment('SUPABASE_TEST_URL')
    : Platform.environment['SUPABASE_TEST_URL'] ?? '';
final _anonKey =
    const String.fromEnvironment('SUPABASE_TEST_ANON_KEY').isNotEmpty
    ? const String.fromEnvironment('SUPABASE_TEST_ANON_KEY')
    : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';
final _email = const String.fromEnvironment('SUPABASE_TEST_EMAIL').isNotEmpty
    ? const String.fromEnvironment('SUPABASE_TEST_EMAIL')
    : Platform.environment['SUPABASE_TEST_EMAIL'] ?? '';
final _password =
    const String.fromEnvironment('SUPABASE_TEST_PASSWORD').isNotEmpty
    ? const String.fromEnvironment('SUPABASE_TEST_PASSWORD')
    : Platform.environment['SUPABASE_TEST_PASSWORD'] ?? '';

void main() {
  late SupabaseClient client;
  String? productId;
  String? customerId;
  String? batchId;

  setUpAll(() async {
    if (!_run) return;
    if ([_url, _anonKey, _email, _password].any((value) => value.isEmpty)) {
      fail('All SUPABASE_TEST_* dart-defines are required.');
    }
    client = SupabaseClient(_url, _anonKey);
    await client.auth.signInWithPassword(email: _email, password: _password);
  });

  tearDownAll(() async {
    if (!_run) return;
    if (batchId != null) {
      await client
          .from('batches')
          .update({'locked': false, 'remitted': false})
          .eq('id', batchId!);
      await client.from('sales').delete().eq('batch_id', batchId!);
      await client.from('batches').delete().eq('id', batchId!);
    }
    if (customerId != null) {
      await client.from('customers').delete().eq('id', customerId!);
    }
    if (productId != null) {
      await client.from('products').delete().eq('id', productId!);
    }
    await client.dispose();
  });

  test('atomic allocation rejects one of two concurrent oversells', () async {
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final product = await client
        .from('products')
        .insert({'title': 'Integration product $suffix'})
        .select('id')
        .single();
    productId = product['id'] as String;
    final customer = await client
        .from('customers')
        .insert({'name': 'Integration customer $suffix'})
        .select('id')
        .single();
    customerId = customer['id'] as String;
    final batch = await client
        .from('batches')
        .insert({
          'product_id': productId,
          'batch_date': '2026-10-19',
          'count_produced': 10,
          'unit_price': 10,
          'total_value': 100,
        })
        .select('id')
        .single();
    batchId = batch['id'] as String;

    Future<Object?> allocate() async {
      try {
        await client.rpc(
          'create_sale_atomic',
          params: {
            'p_batch_id': batchId,
            'p_customer_id': customerId,
            'p_sale_date': '2026-10-19',
            'p_quantity': 6,
            'p_amount': 60,
            'p_discount': 0,
            'p_paid': false,
            'p_date_paid': null,
            'p_payment_method': null,
            'p_sale_type': 'customer_sale',
            'p_notes': null,
            'p_is_reservation': false,
          },
        );
        return null;
      } catch (error) {
        return error;
      }
    }

    final results = await Future.wait([allocate(), allocate()]);
    expect(results.where((result) => result == null), hasLength(1));
    expect(results.whereType<PostgrestException>(), hasLength(1));
  }, skip: !_run);

  test('remitted batches reject sale mutation until reopened', () async {
    await client
        .from('batches')
        .update({'locked': true, 'remitted': true})
        .eq('id', batchId!);
    final sale = await client
        .from('sales')
        .select('id')
        .eq('batch_id', batchId!)
        .single();

    await expectLater(
      client.from('sales').update({'amount': 55}).eq('id', sale['id']),
      throwsA(isA<PostgrestException>()),
    );
  }, skip: !_run);

  test('failed restore rolls back rows inserted earlier in the RPC', () async {
    const uuid = Uuid();
    final restoreProductId = uuid.v4();
    final backup = <String, dynamic>{
      'version': 2,
      'exported_at': '2026-10-19T12:00:00Z',
      'products': [
        {
          'id': 1,
          'remote_id': restoreProductId,
          'title': 'Must roll back',
          'category': 'bakery',
          'updated_at': '2026-10-19T12:00:00Z',
        },
      ],
      'customers': <Object>[],
      'batches': <Object>[],
      'sales': <Object>[],
      'sale_payments': <Object>[],
      'customer_credits': <Object>[],
      'loyalty_adjustments': <Object>[],
      'expenses': [
        {
          'id': 1,
          'remote_id': uuid.v4(),
          'amount': 'not-a-number',
          'expense_date': '2026-10-19',
          'updated_at': '2026-10-19T12:00:00Z',
        },
      ],
      'customer_favorites': <Object>[],
      'favorite_dismissals': <Object>[],
    };

    await expectLater(
      client.rpc(
        'restore_backup_v2',
        params: {'p_backup': backup, 'p_allow_stale': true},
      ),
      throwsA(isA<PostgrestException>()),
    );
    final rows = await client
        .from('products')
        .select('id')
        .eq('id', restoreProductId);
    expect(rows, isEmpty);
  }, skip: !_run);
}
