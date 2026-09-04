import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'restore_report.dart';

String _normalize(String s) => s.trim().toLowerCase();
String? _dateOnly(String? iso) =>
    iso == null ? null : DateTime.parse(iso).toIso8601String().split('T').first;

/// Restores a JSON backup produced by `backup_service.dart` directly into
/// Supabase. Safe to re-run: rows are matched first by `remote_id` (the
/// Supabase row's own id, so this is really a same-row update once synced),
/// then by a natural key (product title, customer name, batch/sale
/// `legacy_id`), so restoring the same backup twice - or restoring an older
/// backup on top of newer data - updates matching rows instead of
/// duplicating them.
class BackupRestoreService {
  final SupabaseClient client;
  const BackupRestoreService(this.client);

  Future<RestoreReport> restore(Uint8List bytes) async {
    final report = RestoreReport();
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    final productIds = await _restoreProducts(
      (data['products'] as List?) ?? [],
      report,
    );
    final customerIds = await _restoreCustomers(
      (data['customers'] as List?) ?? [],
      report,
    );
    final batchIds = await _restoreBatches(
      (data['batches'] as List?) ?? [],
      productIds,
      report,
    );
    await _restoreSales(
      (data['sales'] as List?) ?? [],
      batchIds,
      customerIds,
      report,
    );

    return report;
  }

  Future<Map<int, String>> _restoreProducts(
    List raw,
    RestoreReport report,
  ) async {
    final idMap = <int, String>{};
    final existing = await client
        .from('products')
        .select('id, title, image_url, category, is_archived');
    final byId = {for (final r in existing) r['id'] as String: r};
    final byTitle = {
      for (final r in existing) _normalize(r['title'] as String): r,
    };

    for (final entry in raw) {
      final m = entry as Map<String, dynamic>;
      final oldId = m['id'] as int;
      final title = m['title'] as String? ?? '';
      if (title.isEmpty) {
        report.add('A backed-up product has no title; skipped');
        continue;
      }
      final remoteId = m['remote_id'] as String?;
      final imageUrl = m['image_url'] as String?;
      // Older backups predate categories/archiving - default to the same
      // values a freshly-created product would get.
      final category = m['category'] as String? ?? 'bakery';
      final isArchived = m['is_archived'] as bool? ?? false;

      final match = (remoteId != null ? byId[remoteId] : null) ??
          byTitle[_normalize(title)];

      if (match == null) {
        final inserted = await client
            .from('products')
            .insert({
              'title': title,
              'image_url': imageUrl,
              'category': category,
              'is_archived': isArchived,
            })
            .select('id')
            .single();
        idMap[oldId] = inserted['id'] as String;
        report.productsCreated++;
        continue;
      }

      final matchId = match['id'] as String;
      idMap[oldId] = matchId;
      final changed = match['title'] != title ||
          match['image_url'] != imageUrl ||
          match['category'] != category ||
          match['is_archived'] != isArchived;
      if (!changed) {
        report.productsUnchanged++;
        continue;
      }
      await client.from('products').update({
        'title': title,
        'image_url': imageUrl,
        'category': category,
        'is_archived': isArchived,
      }).eq('id', matchId);
      report.productsUpdated++;
    }
    return idMap;
  }

  Future<Map<int, String>> _restoreCustomers(
    List raw,
    RestoreReport report,
  ) async {
    final idMap = <int, String>{};
    final existing = await client
        .from('customers')
        .select('id, name, phone, is_archived, group_name');
    final byId = {for (final r in existing) r['id'] as String: r};
    final byName = {
      for (final r in existing) _normalize(r['name'] as String): r,
    };

    for (final entry in raw) {
      final m = entry as Map<String, dynamic>;
      final oldId = m['id'] as int;
      final name = m['name'] as String? ?? '';
      if (name.isEmpty) {
        report.add('A backed-up customer has no name; skipped');
        continue;
      }
      final remoteId = m['remote_id'] as String?;
      final phone = m['phone'] as String?;
      final isArchived = m['is_archived'] as bool? ?? false;
      final groupName = m['group_name'] as String?;

      final match =
          (remoteId != null ? byId[remoteId] : null) ?? byName[_normalize(name)];

      if (match == null) {
        final inserted = await client
            .from('customers')
            .insert({
              'name': name,
              'phone': phone,
              'is_archived': isArchived,
              'group_name': groupName,
            })
            .select('id')
            .single();
        idMap[oldId] = inserted['id'] as String;
        report.customersCreated++;
        continue;
      }

      final matchId = match['id'] as String;
      idMap[oldId] = matchId;
      final changed = match['name'] != name ||
          match['phone'] != phone ||
          match['is_archived'] != isArchived ||
          match['group_name'] != groupName;
      if (!changed) {
        report.customersUnchanged++;
        continue;
      }
      await client.from('customers').update({
        'name': name,
        'phone': phone,
        'is_archived': isArchived,
        'group_name': groupName,
      }).eq('id', matchId);
      report.customersUpdated++;
    }
    return idMap;
  }

  Future<Map<int, String>> _restoreBatches(
    List raw,
    Map<int, String> productIds,
    RestoreReport report,
  ) async {
    final idMap = <int, String>{};
    final existing = await client.from('batches').select(
        'id, legacy_id, product_id, batch_date, count_produced, unit_price, unit_cost, total_value, remitted, date_remitted, locked, is_personal');
    final byId = {for (final r in existing) r['id'] as String: r};
    final byLegacy = <int, Map<String, dynamic>>{
      for (final r in existing)
        if (r['legacy_id'] != null) r['legacy_id'] as int: r,
    };

    for (final entry in raw) {
      final m = entry as Map<String, dynamic>;
      final oldId = m['id'] as int;
      final oldProductId = m['product_id'] as int;
      final newProductId = productIds[oldProductId];
      if (newProductId == null) {
        report.add('A backed-up batch references a product that could not '
            'be restored; skipped');
        continue;
      }
      final remoteId = m['remote_id'] as String?;
      final legacyId = m['legacy_id'] as int?;
      final batchDate = _dateOnly(m['batch_date'] as String)!;
      final countProduced = m['count_produced'] as int;
      final unitPrice = (m['unit_price'] as num).toDouble();
      final unitCost = (m['unit_cost'] as num?)?.toDouble() ?? 0;
      final totalValue = (m['total_value'] as num).toDouble();
      final remitted = m['remitted'] as bool? ?? false;
      final dateRemitted = _dateOnly(m['date_remitted'] as String?);
      final locked = m['locked'] as bool? ?? false;
      final isPersonal = m['is_personal'] as bool? ?? false;

      final match = (remoteId != null ? byId[remoteId] : null) ??
          (legacyId != null ? byLegacy[legacyId] : null);

      final payload = {
        'product_id': newProductId,
        'legacy_id': legacyId,
        'batch_date': batchDate,
        'count_produced': countProduced,
        'unit_price': unitPrice,
        'unit_cost': unitCost,
        'total_value': totalValue,
        'remitted': remitted,
        'date_remitted': dateRemitted,
        'locked': locked,
        'is_personal': isPersonal,
      };

      if (match == null) {
        final inserted =
            await client.from('batches').insert(payload).select('id').single();
        idMap[oldId] = inserted['id'] as String;
        report.batchesCreated++;
        continue;
      }

      final matchId = match['id'] as String;
      idMap[oldId] = matchId;
      final changed = match['product_id'] != newProductId ||
          match['batch_date'] != batchDate ||
          match['count_produced'] != countProduced ||
          (match['unit_price'] as num).toDouble() != unitPrice ||
          (match['unit_cost'] as num).toDouble() != unitCost ||
          (match['total_value'] as num).toDouble() != totalValue ||
          match['remitted'] != remitted ||
          match['date_remitted'] != dateRemitted ||
          match['locked'] != locked ||
          match['is_personal'] != isPersonal;
      if (!changed) {
        report.batchesUnchanged++;
        continue;
      }
      await client.from('batches').update(payload).eq('id', matchId);
      report.batchesUpdated++;
    }
    return idMap;
  }

  Future<void> _restoreSales(
    List raw,
    Map<int, String> batchIds,
    Map<int, String> customerIds,
    RestoreReport report,
  ) async {
    final existing = await client.from('sales').select(
        'id, legacy_id, batch_id, customer_id, sale_date, quantity, amount, paid, date_paid, sale_type, notes');
    final byId = {for (final r in existing) r['id'] as String: r};
    final byLegacy = <int, Map<String, dynamic>>{
      for (final r in existing)
        if (r['legacy_id'] != null) r['legacy_id'] as int: r,
    };

    for (final entry in raw) {
      final m = entry as Map<String, dynamic>;
      final oldBatchId = m['batch_id'] as int;
      final oldCustomerId = m['customer_id'] as int;
      final newBatchId = batchIds[oldBatchId];
      final newCustomerId = customerIds[oldCustomerId];
      if (newBatchId == null || newCustomerId == null) {
        report.add('A backed-up transaction references a batch or customer '
            'that could not be restored; skipped');
        continue;
      }
      final remoteId = m['remote_id'] as String?;
      final legacyId = m['legacy_id'] as int?;
      final saleDate = _dateOnly(m['sale_date'] as String)!;
      final quantity = m['quantity'] as int? ?? 1;
      final amount = (m['amount'] as num).toDouble();
      final paid = m['paid'] as bool? ?? false;
      final datePaid = _dateOnly(m['date_paid'] as String?);
      final saleType = m['sale_type'] as String? ?? 'customer_sale';
      final notes = m['notes'] as String?;

      final match = (remoteId != null ? byId[remoteId] : null) ??
          (legacyId != null ? byLegacy[legacyId] : null);

      final payload = {
        'batch_id': newBatchId,
        'customer_id': newCustomerId,
        'legacy_id': legacyId,
        'sale_date': saleDate,
        'quantity': quantity,
        'amount': amount,
        'paid': paid,
        'date_paid': datePaid,
        'sale_type': saleType,
        'notes': notes,
      };

      if (match == null) {
        await client.from('sales').insert(payload);
        report.salesCreated++;
        continue;
      }

      final matchId = match['id'] as String;
      final changed = match['batch_id'] != newBatchId ||
          match['customer_id'] != newCustomerId ||
          match['sale_date'] != saleDate ||
          match['quantity'] != quantity ||
          (match['amount'] as num).toDouble() != amount ||
          match['paid'] != paid ||
          match['date_paid'] != datePaid ||
          match['sale_type'] != saleType ||
          match['notes'] != notes;
      if (!changed) {
        report.salesUnchanged++;
        continue;
      }
      await client.from('sales').update(payload).eq('id', matchId);
      report.salesUpdated++;
    }
  }
}
