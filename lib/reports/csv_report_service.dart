import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/app_date_format.dart';
import '../utils/web_download.dart';

String _csvField(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(',') || s.contains('"') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// A sales ledger for the given date range (inclusive), one row per
/// transaction, joined with product/customer/batch names so it reads
/// standalone in a spreadsheet - no other export needed to make sense of it.
String buildSalesCsv(
  AppState state, {
  DateTime? start,
  DateTime? end,
}) {
  final rows = state.sales.where((s) {
    if (s.isDeleted) return false;
    if (start != null && s.saleDate.isBefore(start)) return false;
    if (end != null && s.saleDate.isAfter(end)) return false;
    return true;
  }).toList()
    ..sort((a, b) => a.saleDate.compareTo(b.saleDate));

  final buffer = StringBuffer();
  buffer.writeln([
    'Sale Date',
    'Product',
    'Category',
    'Customer',
    'Batch Date',
    'Quantity',
    'Unit Price',
    'Amount',
    'Sale Type',
    'Paid',
    'Date Paid',
    'Notes',
  ].map(_csvField).join(','));

  for (final s in rows) {
    final batch = state.batchById(s.batchId);
    final product = batch == null ? null : state.productById(batch.productId);
    final customer = state.customerById(s.customerId);
    buffer.writeln([
      appDateFormat.format(s.saleDate),
      product?.title ?? '',
      product == null ? '' : _categoryLabel(product.category),
      customer?.name ?? '',
      batch == null ? '' : appDateFormat.format(batch.batchDate),
      s.quantity,
      batch?.unitPrice ?? '',
      s.amount.toStringAsFixed(2),
      _saleTypeLabel(s.saleType),
      s.saleType == SaleType.customerSale ? (s.paid ? 'Yes' : 'No') : '',
      s.datePaid == null ? '' : appDateFormat.format(s.datePaid!),
      s.notes ?? '',
    ].map(_csvField).join(','));
  }

  final totalAmount = rows.fold<double>(0, (sum, s) => sum + s.amount);
  buffer.writeln();
  buffer.writeln('${_csvField('Total')},,,,,,,${totalAmount.toStringAsFixed(2)}');

  return buffer.toString();
}

String _categoryLabel(ProductCategory category) {
  switch (category) {
    case ProductCategory.bakery:
      return 'Bakery';
    case ProductCategory.merchandise:
      return 'Merchandise';
  }
}

String _saleTypeLabel(SaleType type) {
  switch (type) {
    case SaleType.customerSale:
      return 'Customer sale';
    case SaleType.unsold:
      return 'Unsold';
    case SaleType.internalConsumption:
      return 'Internal consumption';
    case SaleType.pointsRedemption:
      return 'Points redemption';
  }
}

/// Shares the CSV via the native share sheet on mobile; on web, triggers a
/// plain browser download instead of the Web Share API's share dialog.
Future<void> exportSalesCsv(
  AppState state, {
  DateTime? start,
  DateTime? end,
  required String rangeLabel,
}) async {
  final csv = buildSalesCsv(state, start: start, end: end);
  final fileName =
      'sales_report_${rangeLabel}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
  final bytes = utf8.encode(csv);

  if (kIsWeb) {
    downloadBytes(bytes, fileName, 'text/csv');
    return;
  }

  final file = XFile.fromData(
    bytes,
    name: fileName,
    mimeType: 'text/csv',
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      subject: 'My Bakery sales report',
      text: 'My Bakery sales report',
    ),
  );
}
