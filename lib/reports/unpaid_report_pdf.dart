import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../analytics/customer_calculations.dart';
import '../app_state.dart';
import '../models/sale.dart';
import '../utils/app_date_format.dart';
import '../utils/web_download.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
const _defaultBrandColor = PdfColor.fromInt(0xFFB5651D);

pw.Widget _cell(
  String text, {
  bool bold = false,
  pw.TextAlign align = pw.TextAlign.left,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

/// An internal report of every unpaid `customer_sale` row in [unpaidSales],
/// grouped by customer with a subtotal each, plus a grand total - meant for
/// the owner's own records (chasing collections), not for sharing with a
/// customer the way the per-customer statement is.
Future<Uint8List> buildUnpaidReportPdf(
  AppState state,
  List<Sale> unpaidSales, {
  required String businessName,
  PdfColor? brandColor,
}) async {
  final brand = brandColor ?? _defaultBrandColor;
  final now = DateTime.now();

  final byCustomer = <int, List<Sale>>{};
  for (final s in unpaidSales) {
    byCustomer.putIfAbsent(s.customerId, () => []).add(s);
  }
  final customerIds = byCustomer.keys.toList()
    ..sort((a, b) {
      final nameA = state.customerById(a)?.name ?? '';
      final nameB = state.customerById(b)?.name ?? '';
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });

  double remainingFor(Sale s) => saleRemainingAmount(s, state.salePayments);

  final grandTotal =
      unpaidSales.fold<double>(0, (sum, s) => sum + remainingFor(s));

  String productTitle(Sale s) {
    final batch = state.batchById(s.batchId);
    if (batch == null) return '';
    return state.productById(batch.productId)?.title ?? '';
  }

  double? unitPriceFor(Sale s) => state.batchById(s.batchId)?.unitPrice;

  final regularFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();
  pw.MemoryImage? logo;
  try {
    final bytes = await rootBundle.load('assets/images/logo_square.png');
    logo = pw.MemoryImage(bytes.buffer.asUint8List());
  } catch (_) {
    // Missing asset shouldn't fail the whole report.
  }

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => context.pageNumber == 1
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        if (logo != null) ...[
                          pw.Image(logo, width: 60, height: 60),
                          pw.SizedBox(width: 10),
                        ],
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              businessName,
                              style: pw.TextStyle(
                                fontSize: 24,
                                fontWeight: pw.FontWeight.bold,
                                color: brand,
                              ),
                            ),
                            pw.Text(
                              'Unpaid Report',
                              style: const pw.TextStyle(
                                fontSize: 11,
                                color: PdfColors.grey700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.Text(
                      appDateTimeFormat.format(now),
                      style:
                          const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Divider(color: brand, thickness: 1.5),
                pw.SizedBox(height: 16),
              ],
            )
          : pw.SizedBox.shrink(),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        if (unpaidSales.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.green50,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'No unpaid transactions in the selected batches.',
              style: const pw.TextStyle(fontSize: 12),
            ),
          )
        else ...[
          pw.Table(
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(2.8),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(1.4),
              4: pw.FlexColumnWidth(1.8),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: brand),
                children: [
                  _cell('Date', bold: true),
                  _cell('Item', bold: true),
                  _cell('Unit price', bold: true, align: pw.TextAlign.right),
                  _cell('Qty', bold: true, align: pw.TextAlign.right),
                  _cell('Amount', bold: true, align: pw.TextAlign.right),
                ].map((w) => pw.DefaultTextStyle(
                      style: const pw.TextStyle(color: PdfColors.white),
                      child: w,
                    )).toList(),
              ),
              for (final customerId in customerIds) ...[
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell(state.customerById(customerId)?.name ?? 'Unknown customer',
                        bold: true),
                    _cell(''),
                    _cell(''),
                    _cell(''),
                    _cell(''),
                  ],
                ),
                for (final s in byCustomer[customerId]!
                  ..sort((a, b) => a.saleDate.compareTo(b.saleDate)))
                  pw.TableRow(children: [
                    _cell(appDateFormat.format(s.saleDate)),
                    _cell(productTitle(s)),
                    _cell(
                      unitPriceFor(s) == null
                          ? ''
                          : _currency.format(unitPriceFor(s)),
                      align: pw.TextAlign.right,
                    ),
                    _cell('${s.quantity}', align: pw.TextAlign.right),
                    _cell(_currency.format(remainingFor(s)),
                        align: pw.TextAlign.right),
                  ]),
                if (byCustomer[customerId]!.length > 1)
                  pw.TableRow(children: [
                    _cell(''),
                    _cell(''),
                    _cell(''),
                    _cell('Subtotal', bold: true, align: pw.TextAlign.right),
                    _cell(
                      _currency.format(byCustomer[customerId]!
                          .fold<double>(0, (sum, s) => sum + remainingFor(s))),
                      bold: true,
                      align: pw.TextAlign.right,
                    ),
                  ]),
              ],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(color: brand, thickness: 1.5),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'Grand Total Unpaid: ${_currency.format(grandTotal)}',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

/// Shares the PDF via the native share sheet on mobile; on web, triggers a
/// plain browser download instead of the Web Share API's share dialog.
Future<void> shareUnpaidReport(
  AppState state,
  List<Sale> unpaidSales, {
  required String businessName,
  PdfColor? brandColor,
}) async {
  final bytes = await buildUnpaidReportPdf(
    state,
    unpaidSales,
    businessName: businessName,
    brandColor: brandColor,
  );
  final fileName =
      'unpaid_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

  if (kIsWeb) {
    downloadBytes(bytes, fileName, 'application/pdf');
    return;
  }

  final file = XFile.fromData(
    bytes,
    name: fileName,
    mimeType: 'application/pdf',
  );
  await SharePlus.instance.share(
    ShareParams(
      files: [file],
      fileNameOverrides: [fileName],
      subject: '$businessName - unpaid report',
      text: 'Unpaid report from $businessName.',
    ),
  );
}
