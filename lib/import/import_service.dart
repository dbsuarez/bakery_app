import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'import_report.dart';
import 'xlsx_parser.dart';

String _normalize(String s) => s.trim().toLowerCase();
String _dateOnly(DateTime dt) => dt.toIso8601String().split('T').first;

class _BatchInfo {
  final String uuid;
  final double unitPrice;
  final bool locked;
  final bool isNew;
  const _BatchInfo(this.uuid, this.unitPrice, this.locked, this.isNew);
}

/// Imports the legacy AR Spreadsheet directly into Supabase per spec
/// section 13: products/customers first, then batches (upsert by
/// `legacy_id`), then sales (upsert by `legacy_id`). Idempotent - importing
/// the same file twice produces no duplicates or spurious changes, and
/// issues are surfaced in the returned [ImportReport] rather than silently
/// "fixed" (spec section 2).
class ImportService {
  final SupabaseClient client;
  const ImportService(this.client);

  Future<ImportReport> importWorkbook(Uint8List bytes) async {
    final report = ImportReport();
    final workbook = parseBakeryWorkbook(bytes, report);

    await _cleanUpLegacyUnsoldCustomer(report);
    final productIds = await _importProducts(workbook.products, report);
    final customerIds = await _importCustomers(workbook.customers, report);
    final batchInfo = await _importBatches(
      workbook.batches,
      productIds,
      report,
    );
    await _importSales(workbook.sales, batchInfo, customerIds, report);
    await _checkAllocations(batchInfo.values.toSet(), report);

    return report;
  }

  /// "Unsold" was a spreadsheet-era workaround (a fake customer standing in
  /// for unsold inventory). This app computes unsold value directly from a
  /// batch's remaining quantity instead, so any leftover "Unsold" customer
  /// and its sale rows from a previous import are archived/removed here.
  Future<void> _cleanUpLegacyUnsoldCustomer(ImportReport report) async {
    final unsold = await client
        .from('customers')
        .select('id')
        .eq('name', 'Unsold')
        .eq('is_deleted', false)
        .maybeSingle();
    if (unsold == null) return;
    final unsoldId = unsold['id'] as String;

    final sales = await client
        .from('sales')
        .select('id')
        .eq('customer_id', unsoldId)
        .eq('is_deleted', false);
    for (final sale in sales) {
      await client
          .from('sales')
          .update({'is_deleted': true})
          .eq('id', sale['id'] as String);
    }
    await client
        .from('customers')
        .update({'is_archived': true, 'is_deleted': true})
        .eq('id', unsoldId);
    report.add(
      ImportIssueCategory.pseudoCustomerClassification,
      'Removed the legacy "Unsold" customer and ${sales.length} sale row(s); '
      'unsold inventory is now computed from batch remaining quantity',
    );
  }

  Future<Map<String, String>> _importProducts(
    List<ParsedProduct> parsed,
    ImportReport report,
  ) async {
    final map = <String, String>{};
    final existing = await client
        .from('products')
        .select('id, title')
        .eq('is_deleted', false);
    for (final row in existing) {
      map[_normalize(row['title'] as String)] = row['id'] as String;
    }
    for (final product in parsed) {
      final key = _normalize(product.title);
      if (map.containsKey(key)) continue;
      final inserted = await client
          .from('products')
          .insert({'title': product.title})
          .select('id')
          .single();
      map[key] = inserted['id'] as String;
      report.productsCreated++;
    }
    return map;
  }

  Future<Map<String, String>> _importCustomers(
    List<ParsedCustomer> parsed,
    ImportReport report,
  ) async {
    final map = <String, String>{};
    final existing = await client
        .from('customers')
        .select('id, name')
        .eq('is_deleted', false);
    for (final row in existing) {
      map[_normalize(row['name'] as String)] = row['id'] as String;
    }
    final seenKeys = <String, String>{};
    for (final customer in parsed) {
      if (customer.name == 'Unsold') {
        // No longer imported: unsold inventory is computed from batch
        // remaining quantity instead of a placeholder customer.
        continue;
      }
      final key = _normalize(customer.name);
      if (seenKeys.containsKey(key) && seenKeys[key] != customer.name) {
        report.add(
          ImportIssueCategory.duplicateCustomerName,
          '"${seenKeys[key]}" and "${customer.name}" both normalize to the same customer',
        );
      }
      seenKeys[key] = customer.name;
      if (map.containsKey(key)) continue;
      final inserted = await client
          .from('customers')
          .insert({'name': customer.name})
          .select('id')
          .single();
      map[key] = inserted['id'] as String;
      report.customersCreated++;
    }
    return map;
  }

  Future<Map<int, _BatchInfo>> _importBatches(
    List<ParsedBatch> parsed,
    Map<String, String> productIds,
    ImportReport report,
  ) async {
    final result = <int, _BatchInfo>{};
    final seenLegacyIds = <int>{};

    // Suspicious count/price inversion: same product, one row's count/price
    // is the other's price/count swapped (spec section 2 finding).
    final byProduct = <String, List<ParsedBatch>>{};
    for (final b in parsed) {
      byProduct.putIfAbsent(_normalize(b.productName), () => []).add(b);
    }
    for (final group in byProduct.values) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          final a = group[i], b = group[j];
          if (a.count == null || a.price == null) continue;
          if (b.count == null || b.price == null) continue;
          if (a.count == a.price) continue; // not distinguishable, skip
          if (a.count == b.price && a.price == b.count) {
            report.add(
              ImportIssueCategory.suspiciousInversion,
              'Batch #${a.legacyId} (count ${a.count}, price ${a.price}) and '
              'batch #${b.legacyId} (count ${b.count}, price ${b.price}) for '
              '"${a.productName}" look like count/price were swapped on one of them',
            );
          }
        }
      }
    }

    final existingRows = await client
        .from('batches')
        .select(
          'id, legacy_id, product_id, batch_date, count_produced, unit_price, remitted, date_remitted, locked',
        )
        .eq('is_deleted', false);
    final byLegacyId = <int, Map<String, dynamic>>{
      for (final r in existingRows)
        if (r['legacy_id'] != null) r['legacy_id'] as int: r,
    };

    for (final batch in parsed) {
      if (!seenLegacyIds.add(batch.legacyId)) {
        report.add(
          ImportIssueCategory.duplicateLegacyId,
          'Duplicate batch legacy id #${batch.legacyId} in tblRemittance; only the first occurrence was imported',
        );
        continue;
      }

      final productId = productIds[_normalize(batch.productName)];
      if (productId == null) {
        report.add(
          ImportIssueCategory.unknownReference,
          'Batch #${batch.legacyId} references unknown product "${batch.productName}"; skipped',
        );
        continue;
      }
      if (batch.count == null ||
          batch.count! <= 0 ||
          batch.price == null ||
          batch.price! < 0) {
        report.add(
          ImportIssueCategory.invalidDateOrAmount,
          'Batch #${batch.legacyId} has an invalid count (${batch.count}) or price (${batch.price})',
        );
        continue;
      }
      if (batch.date == null) {
        report.add(
          ImportIssueCategory.invalidDateOrAmount,
          'Batch #${batch.legacyId} has a missing/invalid date; defaulted to today',
        );
      }

      final countProduced = batch.count!.round();
      final unitPrice = batch.price!;
      final totalValue = countProduced * unitPrice;
      final batchDate = batch.date ?? DateTime.now();

      final existing = byLegacyId[batch.legacyId];

      if (existing == null) {
        final inserted = await client
            .from('batches')
            .insert({
              'legacy_id': batch.legacyId,
              'product_id': productId,
              'batch_date': _dateOnly(batchDate),
              'count_produced': countProduced,
              'unit_price': unitPrice,
              'total_value': totalValue,
              'remitted': batch.remitted,
              'date_remitted': batch.dateRemitted != null
                  ? _dateOnly(batch.dateRemitted!)
                  : null,
              'locked': batch.remitted,
            })
            .select('id')
            .single();
        final uuid = inserted['id'] as String;
        result[batch.legacyId] = _BatchInfo(
          uuid,
          unitPrice,
          batch.remitted,
          true,
        );
        report.batchesCreated++;
        continue;
      }

      final existingUuid = existing['id'] as String;
      final existingProductId = existing['product_id'] as String;
      final existingBatchDate = DateTime.parse(
        existing['batch_date'] as String,
      );
      final existingCountProduced = existing['count_produced'] as int;
      final existingUnitPrice = (existing['unit_price'] as num).toDouble();
      final existingRemitted = existing['remitted'] as bool;
      final existingDateRemitted = existing['date_remitted'] == null
          ? null
          : DateTime.parse(existing['date_remitted'] as String);
      final existingLocked = existing['locked'] as bool;

      final changed =
          existingProductId != productId ||
          existingCountProduced != countProduced ||
          existingUnitPrice != unitPrice ||
          existingBatchDate !=
              DateTime(batchDate.year, batchDate.month, batchDate.day) ||
          existingRemitted != batch.remitted ||
          existingDateRemitted != batch.dateRemitted;

      if (!changed) {
        result[batch.legacyId] = _BatchInfo(
          existingUuid,
          existingUnitPrice,
          existingLocked,
          false,
        );
        report.batchesUnchanged++;
        continue;
      }

      if (existingLocked) {
        report.add(
          ImportIssueCategory.lockedBatchConflict,
          'Batch #${batch.legacyId} is locked (remitted) locally and the spreadsheet has different metadata for it; the spreadsheet values were NOT applied',
        );
        result[batch.legacyId] = _BatchInfo(
          existingUuid,
          existingUnitPrice,
          existingLocked,
          false,
        );
        report.batchesUnchanged++;
        continue;
      }

      await client
          .from('batches')
          .update({
            'product_id': productId,
            'batch_date': _dateOnly(batchDate),
            'count_produced': countProduced,
            'unit_price': unitPrice,
            'total_value': totalValue,
            'remitted': batch.remitted,
            'date_remitted': batch.dateRemitted != null
                ? _dateOnly(batch.dateRemitted!)
                : null,
            'locked': batch.remitted,
          })
          .eq('id', existingUuid);
      result[batch.legacyId] = _BatchInfo(
        existingUuid,
        unitPrice,
        batch.remitted,
        false,
      );
      report.batchesUpdated++;
    }

    return result;
  }

  Future<void> _importSales(
    List<ParsedSale> parsed,
    Map<int, _BatchInfo> batchInfo,
    Map<String, String> customerIds,
    ImportReport report,
  ) async {
    final seenLegacyIds = <int>{};

    final existingRows = await client
        .from('sales')
        .select('id, legacy_id')
        .eq('is_deleted', false);
    final byLegacyId = <int, String>{
      for (final r in existingRows)
        if (r['legacy_id'] != null) r['legacy_id'] as int: r['id'] as String,
    };

    for (final sale in parsed) {
      if (!seenLegacyIds.add(sale.legacyId)) {
        report.add(
          ImportIssueCategory.duplicateLegacyId,
          'Duplicate transaction legacy id #${sale.legacyId} in tblTransactions; only the first occurrence was imported',
        );
        continue;
      }

      if (sale.customerName == 'Unsold') {
        // No longer imported as a sale row: unsold inventory is computed
        // from batch remaining quantity instead.
        continue;
      }

      final batch = batchInfo[sale.batchLegacyId];
      if (batch == null) {
        report.add(
          ImportIssueCategory.unknownReference,
          'Transaction #${sale.legacyId} references unknown batch #${sale.batchLegacyId}; skipped',
        );
        continue;
      }
      final customerId = customerIds[_normalize(sale.customerName)];
      if (customerId == null) {
        report.add(
          ImportIssueCategory.unknownReference,
          'Transaction #${sale.legacyId} references unknown customer "${sale.customerName}"; skipped',
        );
        continue;
      }

      final amount = sale.amount;
      if (amount == null) {
        report.add(
          ImportIssueCategory.invalidDateOrAmount,
          'Transaction #${sale.legacyId} has a missing/invalid amount; defaulted to 0',
        );
      }
      if (sale.date == null) {
        report.add(
          ImportIssueCategory.invalidDateOrAmount,
          'Transaction #${sale.legacyId} has a missing/invalid date; defaulted to today',
        );
      }

      final saleDate = sale.date ?? DateTime.now();
      final resolvedAmount = amount ?? 0;
      // Classified by the transaction itself, not by who the customer is:
      // a zero-amount row is a freebie/staff sample regardless of customer
      // (the same real customer can otherwise buy and pay normally).
      final saleType = resolvedAmount == 0
          ? 'internal_consumption'
          : 'customer_sale';
      final datePaid = sale.paid ? sale.datePaid : null;

      // The legacy sheet has no quantity column, but the batch's unit price
      // lets us reliably infer it: an amount of 2x the unit price means the
      // customer took 2 units (spec section 2). Only trust the inference
      // when it divides cleanly; otherwise default to 1 and flag for review.
      var quantity = 1;
      if (resolvedAmount > 0 && batch.unitPrice > 0) {
        final ratio = resolvedAmount / batch.unitPrice;
        final rounded = ratio.round();
        if (rounded >= 1 && (ratio - rounded).abs() <= 0.02) {
          quantity = rounded;
        } else if (rounded >= 2) {
          report.add(
            ImportIssueCategory.invalidDateOrAmount,
            'Transaction #${sale.legacyId} amount (₱$resolvedAmount) does not '
            'cleanly divide by batch #${sale.batchLegacyId} unit price '
            '(₱${batch.unitPrice}); quantity defaulted to 1, please review',
          );
        }
      }

      final existingId = byLegacyId[sale.legacyId];

      if (existingId == null) {
        // A batch locked before this import (already remitted via the app)
        // rejects brand-new sales, same as manual entry would. A batch
        // freshly created by this same import run is exempt: we're loading
        // its full historical transaction set in one pass, not adding a new
        // transaction to an already-settled batch after the fact.
        if (!batch.isNew && batch.locked) {
          report.add(
            ImportIssueCategory.lockedBatchConflict,
            'Transaction #${sale.legacyId} targets locked batch #${sale.batchLegacyId}; not imported',
          );
          continue;
        }
        await client.from('sales').insert({
          'legacy_id': sale.legacyId,
          'batch_id': batch.uuid,
          'customer_id': customerId,
          'sale_date': _dateOnly(saleDate),
          'quantity': quantity,
          'amount': resolvedAmount,
          'paid': sale.paid,
          'date_paid': datePaid != null ? _dateOnly(datePaid) : null,
          'sale_type': saleType,
        });
        report.salesCreated++;
        continue;
      }

      await client
          .from('sales')
          .update({
            'batch_id': batch.uuid,
            'customer_id': customerId,
            'sale_date': _dateOnly(saleDate),
            'quantity': quantity,
            'amount': resolvedAmount,
            'paid': sale.paid,
            'date_paid': datePaid != null ? _dateOnly(datePaid) : null,
            'sale_type': saleType,
          })
          .eq('id', existingId);
      report.salesUpdated++;
    }
  }

  Future<void> _checkAllocations(
    Set<_BatchInfo> batches,
    ImportReport report,
  ) async {
    for (final batch in batches) {
      final sales = await client
          .from('sales')
          .select('quantity')
          .eq('batch_id', batch.uuid)
          .eq('is_deleted', false)
          .eq('sale_type', 'customer_sale');
      final allocated = sales.fold<int>(
        0,
        (sum, s) => sum + (s['quantity'] as int),
      );
      final batchRow = await client
          .from('batches')
          .select('count_produced, legacy_id')
          .eq('id', batch.uuid)
          .single();
      final countProduced = batchRow['count_produced'] as int;
      if (allocated > countProduced) {
        report.add(
          ImportIssueCategory.batchAllocationMismatch,
          'Batch #${batchRow['legacy_id'] ?? batch.uuid} allocated $allocated units but only $countProduced were produced',
        );
      }
    }
  }
}
