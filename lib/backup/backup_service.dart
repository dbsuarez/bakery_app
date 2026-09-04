import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models/batch.dart';
import '../models/customer.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/web_download.dart';

/// Builds a full JSON snapshot of the app's data (all products, customers,
/// batches, sales) for manual backup, independent of Supabase/Drift storage.
String buildBackupJson(AppState state) {
  final data = {
    'exported_at': DateTime.now().toIso8601String(),
    'version': 1,
    'products': state.products.map(_productToJson).toList(),
    'customers': state.customers.map(_customerToJson).toList(),
    'batches': state.batches.map(_batchToJson).toList(),
    'sales': state.sales.map(_saleToJson).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// Shares the backup via the native share sheet on mobile; on web, triggers
/// a plain browser download instead of the Web Share API's share dialog.
Future<void> exportBackup(AppState state) async {
  final json = buildBackupJson(state);
  final fileName =
      'bakery_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json';
  final bytes = utf8.encode(json);

  if (kIsWeb) {
    downloadBytes(bytes, fileName, 'application/json');
    return;
  }

  final file = XFile.fromData(
    bytes,
    name: fileName,
    mimeType: 'application/json',
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      subject: 'My Bakery backup',
      text: 'My Bakery data backup',
    ),
  );
}

Map<String, dynamic> _productToJson(Product p) => {
      'id': p.id,
      'remote_id': p.remoteId,
      'title': p.title,
      'image_url': p.imageUrl,
      'category': p.category.value,
      'is_archived': p.isArchived,
      'updated_at': p.updatedAt.toIso8601String(),
    };

Map<String, dynamic> _customerToJson(Customer c) => {
      'id': c.id,
      'remote_id': c.remoteId,
      'name': c.name,
      'phone': c.phone,
      'is_archived': c.isArchived,
      'group_name': c.group,
      'updated_at': c.updatedAt.toIso8601String(),
    };

Map<String, dynamic> _batchToJson(Batch b) => {
      'id': b.id,
      'remote_id': b.remoteId,
      'legacy_id': b.legacyId,
      'product_id': b.productId,
      'batch_date': b.batchDate.toIso8601String(),
      'count_produced': b.countProduced,
      'unit_price': b.unitPrice,
      'unit_cost': b.unitCost,
      'total_value': b.totalValue,
      'remitted': b.remitted,
      'date_remitted': b.dateRemitted?.toIso8601String(),
      'locked': b.locked,
      'is_personal': b.isPersonal,
      'updated_at': b.updatedAt.toIso8601String(),
    };

Map<String, dynamic> _saleToJson(Sale s) => {
      'id': s.id,
      'remote_id': s.remoteId,
      'legacy_id': s.legacyId,
      'batch_id': s.batchId,
      'customer_id': s.customerId,
      'sale_date': s.saleDate.toIso8601String(),
      'quantity': s.quantity,
      'amount': s.amount,
      'paid': s.paid,
      'date_paid': s.datePaid?.toIso8601String(),
      'sale_type': s.saleType.value,
      'notes': s.notes,
      'updated_at': s.updatedAt.toIso8601String(),
    };
