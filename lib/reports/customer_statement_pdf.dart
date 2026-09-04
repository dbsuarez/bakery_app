import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models/customer.dart';
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

/// A one-page "how much do they owe" statement: unpaid customer_sale rows
/// only (spec's balance definition), oldest first, with a running total -
/// meant to be shared as-is to a customer via chat, not archived internally.
Future<Uint8List> buildCustomerStatementPdf(
  AppState state,
  Customer customer, {
  required String businessName,
  PdfColor? brandColor,
}) async {
  final brand = brandColor ?? _defaultBrandColor;
  final unpaid = state.sales
      .where((s) =>
          s.customerId == customer.id &&
          !s.isDeleted &&
          !s.paid &&
          s.saleType == SaleType.customerSale)
      .toList()
    ..sort((a, b) => a.saleDate.compareTo(b.saleDate));

  final total = unpaid.fold<double>(0, (sum, s) => sum + s.amount);
  final now = DateTime.now();

  String productTitle(Sale s) {
    final batch = state.batchById(s.batchId);
    if (batch == null) return '';
    return state.productById(batch.productId)?.title ?? '';
  }

  double? unitPriceFor(Sale s) => state.batchById(s.batchId)?.unitPrice;

  // The PDF core fonts don't cover the peso sign (₱, U+20B1) - Noto Sans
  // does, and the app already requires internet, so fetching it at
  // generation time (cached by the printing package after the first call)
  // is fine.
  final regularFont = await PdfGoogleFonts.notoSansRegular();
  final boldFont = await PdfGoogleFonts.notoSansBold();

  pw.MemoryImage? qrImage;
  if (unpaid.isNotEmpty) {
    try {
      final qrBytes = await rootBundle.load('assets/images/qr_maribank.jpg');
      qrImage = pw.MemoryImage(qrBytes.buffer.asUint8List());
    } catch (_) {
      // Asset missing - skip the QR rather than fail the whole statement.
    }
  }

  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
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
                    'Statement of Account',
                    style: const pw.TextStyle(
                      fontSize: 11,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.Text(
                appDateTimeFormat.format(now),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Divider(color: brand, thickness: 1.5),
          pw.SizedBox(height: 16),
          pw.Text(
            customer.name,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 20),
          if (unpaid.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'No outstanding balance - you\'re all paid up. Thank you!',
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
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(1.6),
                3: pw.FlexColumnWidth(1),
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
                for (final s in unpaid)
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
                    _cell(_currency.format(s.amount), align: pw.TextAlign.right),
                  ]),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                'Total Due: ${_currency.format(total)}',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            if (qrImage != null) ...[
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Scan to pay',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: brand,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Image(qrImage, width: 160),
                  ],
                ),
              ),
            ],
          ],
          pw.Spacer(),
          pw.Divider(color: PdfColors.grey300),
          pw.Text(
            'Thank you for supporting $businessName!',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

/// Shares the PDF via the native share sheet (Messenger, WhatsApp, etc.) on
/// mobile; on web, triggers a plain browser download instead - share_plus
/// would otherwise invoke the Web Share API where supported, popping a share
/// dialog rather than just saving the file.
Future<void> shareCustomerStatement(
  AppState state,
  Customer customer, {
  required String businessName,
  PdfColor? brandColor,
}) async {
  final bytes = await buildCustomerStatementPdf(
    state,
    customer,
    businessName: businessName,
    brandColor: brandColor,
  );
  final safeName = customer.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final fileName =
      'statement_${safeName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';

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
      subject: '$businessName - statement for ${customer.name}',
      text: 'Hi ${customer.name}, here\'s your statement from $businessName.',
    ),
  );
}
