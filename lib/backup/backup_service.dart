import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_state.dart';
import '../models/batch.dart';
import '../models/customer.dart';
import '../models/customer_credit.dart';
import '../models/customer_favorite.dart';
import '../models/expense.dart';
import '../models/favorite_dismissal.dart';
import '../models/loyalty_adjustment.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/web_download.dart';

/// Builds a versioned JSON snapshot of every persisted app data set.
String buildBackupJson(AppState state) {
  final data = buildBackupDocument(
    products: state.products,
    customers: state.customers,
    batches: state.batches,
    sales: state.sales,
    salePayments: state.salePayments,
    customerCredits: state.customerCredits,
    loyaltyAdjustments: state.loyaltyAdjustments,
    expenses: state.expenses,
    customerFavorites: state.customerFavorites,
    favoriteDismissals: state.favoriteDismissals,
  );
  return const JsonEncoder.withIndent('  ').convert(data);
}

/// Pure backup encoder used by the app and by compatibility tests.
Map<String, dynamic> buildBackupDocument({
  DateTime? exportedAt,
  List<Product> products = const [],
  List<Customer> customers = const [],
  List<Batch> batches = const [],
  List<Sale> sales = const [],
  List<SalePayment> salePayments = const [],
  List<CustomerCredit> customerCredits = const [],
  List<LoyaltyAdjustment> loyaltyAdjustments = const [],
  List<Expense> expenses = const [],
  List<CustomerFavorite> customerFavorites = const [],
  List<FavoriteDismissal> favoriteDismissals = const [],
}) {
  final productIds = products.map((row) => row.id).toSet();
  final customerIds = customers.map((row) => row.id).toSet();
  final batchIds = batches.map((row) => row.id).toSet();
  final saleIds = sales.map((row) => row.id).toSet();

  // A parent may be soft-deleted while a dependent ledger/preference row is
  // still live. Snapshot reads intentionally omit deleted parents, so omit
  // those now-unrestorable dependents rather than exporting invalid refs.
  final validPayments = salePayments.where(
    (row) => saleIds.contains(row.saleId),
  );
  final validCredits = customerCredits.where(
    (row) =>
        customerIds.contains(row.customerId) &&
        (row.saleId == null || saleIds.contains(row.saleId)),
  );
  final validAdjustments = loyaltyAdjustments.where(
    (row) => customerIds.contains(row.customerId),
  );
  final validFavorites = customerFavorites.where(
    (row) =>
        customerIds.contains(row.customerId) &&
        productIds.contains(row.productId),
  );
  final validDismissals = favoriteDismissals.where(
    (row) =>
        customerIds.contains(row.customerId) && batchIds.contains(row.batchId),
  );

  return {
    'exported_at': (exportedAt ?? DateTime.now()).toIso8601String(),
    'version': 2,
    'products': products.map(_productToJson).toList(),
    'customers': customers.map(_customerToJson).toList(),
    'batches': batches.map(_batchToJson).toList(),
    'sales': sales.map(_saleToJson).toList(),
    'sale_payments': validPayments.map(_salePaymentToJson).toList(),
    'customer_credits': validCredits.map(_customerCreditToJson).toList(),
    'loyalty_adjustments': validAdjustments
        .map(_loyaltyAdjustmentToJson)
        .toList(),
    'expenses': expenses.map(_expenseToJson).toList(),
    'customer_favorites': validFavorites.map(_customerFavoriteToJson).toList(),
    'favorite_dismissals': validDismissals
        .map(_favoriteDismissalToJson)
        .toList(),
  };
}

/// Shares the backup via the native share sheet on mobile; on web, triggers
/// a plain browser download instead of the Web Share API's share dialog.
Future<void> exportBackup(AppState state) async {
  final json = buildBackupJson(state);
  final fileName =
      'bakery_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.zip';
  final archive = Archive()
    ..addFile(
      ArchiveFile('backup.json', utf8.encode(json).length, utf8.encode(json)),
    );
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser!.id;
  for (final bucket in const ['product-photos', 'qr-codes']) {
    var offset = 0;
    const pageSize = 100;
    while (true) {
      final objects = await client.storage
          .from(bucket)
          .list(
            path: uid,
            searchOptions: SearchOptions(limit: pageSize, offset: offset),
          );
      for (final object in objects.where(
        (object) => object.name != '.emptyFolderPlaceholder',
      )) {
        final bytes = await client.storage
            .from(bucket)
            .download('$uid/${object.name}');
        archive.addFile(
          ArchiveFile('media/$bucket/${object.name}', bytes.length, bytes),
        );
      }
      if (objects.length < pageSize) break;
      offset += objects.length;
    }
  }
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

  if (kIsWeb) {
    downloadBytes(bytes, fileName, 'application/zip');
    return;
  }

  final file = XFile.fromData(
    bytes,
    name: fileName,
    mimeType: 'application/zip',
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
  'discount': s.discount,
  'paid': s.paid,
  'date_paid': s.datePaid?.toIso8601String(),
  'payment_method': s.paymentMethod,
  'sale_type': s.saleType.value,
  'notes': s.notes,
  'is_reservation': s.isReservation,
  'updated_at': s.updatedAt.toIso8601String(),
};

Map<String, dynamic> _salePaymentToJson(SalePayment p) => {
  'id': p.id,
  'remote_id': p.remoteId,
  'sale_id': p.saleId,
  'amount': p.amount,
  'payment_date': p.paymentDate.toIso8601String(),
  'payment_method': p.paymentMethod,
  'notes': p.notes,
  'updated_at': p.updatedAt.toIso8601String(),
};

Map<String, dynamic> _customerCreditToJson(CustomerCredit c) => {
  'id': c.id,
  'remote_id': c.remoteId,
  'customer_id': c.customerId,
  'amount': c.amount,
  'reason': c.reason,
  'sale_id': c.saleId,
  'credit_date': c.creditDate.toIso8601String(),
  'updated_at': c.updatedAt.toIso8601String(),
};

Map<String, dynamic> _loyaltyAdjustmentToJson(LoyaltyAdjustment a) => {
  'id': a.id,
  'remote_id': a.remoteId,
  'customer_id': a.customerId,
  'category': a.category.value,
  'points': a.points,
  'reason': a.reason,
  'adjustment_date': a.adjustmentDate.toIso8601String(),
  'updated_at': a.updatedAt.toIso8601String(),
};

Map<String, dynamic> _expenseToJson(Expense e) => {
  'id': e.id,
  'remote_id': e.remoteId,
  'amount': e.amount,
  'category': e.category,
  'expense_date': e.expenseDate.toIso8601String(),
  'notes': e.notes,
  'updated_at': e.updatedAt.toIso8601String(),
};

Map<String, dynamic> _customerFavoriteToJson(CustomerFavorite f) => {
  'customer_id': f.customerId,
  'product_id': f.productId,
};

Map<String, dynamic> _favoriteDismissalToJson(FavoriteDismissal d) => {
  'customer_id': d.customerId,
  'batch_id': d.batchId,
};
