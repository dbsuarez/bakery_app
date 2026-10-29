import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'import_report.dart';

class ParsedProduct {
  final String title;
  const ParsedProduct(this.title);
}

class ParsedCustomer {
  final String name;
  const ParsedCustomer(this.name);
}

class ParsedBatch {
  final int legacyId;
  final DateTime? date;
  final String productName;
  final double? count;
  final double? price;
  final bool remitted;
  final DateTime? dateRemitted;

  const ParsedBatch({
    required this.legacyId,
    required this.date,
    required this.productName,
    required this.count,
    required this.price,
    required this.remitted,
    required this.dateRemitted,
  });
}

class ParsedSale {
  final int legacyId;
  final int batchLegacyId;
  final DateTime? date;
  final String customerName;
  final double? amount;
  final bool paid;
  final DateTime? datePaid;

  const ParsedSale({
    required this.legacyId,
    required this.batchLegacyId,
    required this.date,
    required this.customerName,
    required this.amount,
    required this.paid,
    required this.datePaid,
  });
}

class ParsedWorkbook {
  final List<ParsedProduct> products;
  final List<ParsedCustomer> customers;
  final List<ParsedBatch> batches;
  final List<ParsedSale> sales;

  const ParsedWorkbook({
    required this.products,
    required this.customers,
    required this.batches,
    required this.sales,
  });
}

String? _asText(CellValue? value) {
  if (value == null) return null;
  if (value is TextCellValue) {
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
  return null;
}

double? _asDouble(CellValue? value) {
  if (value == null) return null;
  if (value is IntCellValue) return value.value.toDouble();
  if (value is DoubleCellValue) return value.value;
  return null;
}

int? _asInt(CellValue? value) {
  final d = _asDouble(value);
  return d?.round();
}

bool _asBool(CellValue? value) {
  if (value is BoolCellValue) return value.value;
  return false;
}

DateTime? _asDate(CellValue? value) {
  if (value is DateCellValue) return value.asDateTimeLocal();
  if (value is DateTimeCellValue) return value.asDateTimeLocal();
  return null;
}

CellValue? _cell(List<Data?> row, int index) {
  if (index >= row.length) return null;
  return row[index]?.value;
}

/// Parses the legacy AR Spreadsheet workbook (spec section 2/13): four
/// sheets `tblProduct`, `tblCustomers`, `tblRemittance`, `tblTransactions`.
/// Only rows with a valid natural key (title/name/id) are kept; trailing
/// blank/formatting rows are skipped and counted in [report].
ParsedWorkbook parseBakeryWorkbook(Uint8List bytes, ImportReport report) {
  final excel = Excel.decodeBytes(bytes);

  Sheet? sheet(String name) => excel.tables[name];

  final products = <ParsedProduct>[];
  final productSheet = sheet('tblProduct');
  int productBlankRows = 0;
  if (productSheet != null) {
    for (var r = 1; r < productSheet.maxRows; r++) {
      final title = _asText(_cell(productSheet.row(r), 0));
      if (title == null) {
        productBlankRows++;
        continue;
      }
      products.add(ParsedProduct(title));
    }
  }
  if (productBlankRows > 0) {
    report.add(
      ImportIssueCategory.blankRowsSkipped,
      '$productBlankRows blank row(s) skipped in tblProduct',
    );
  }

  final customers = <ParsedCustomer>[];
  final customerSheet = sheet('tblCustomers');
  int customerBlankRows = 0;
  if (customerSheet != null) {
    for (var r = 1; r < customerSheet.maxRows; r++) {
      final name = _asText(_cell(customerSheet.row(r), 0));
      if (name == null) {
        customerBlankRows++;
        continue;
      }
      customers.add(ParsedCustomer(name));
    }
  }
  if (customerBlankRows > 0) {
    report.add(
      ImportIssueCategory.blankRowsSkipped,
      '$customerBlankRows blank row(s) skipped in tblCustomers',
    );
  }

  final batches = <ParsedBatch>[];
  final remittanceSheet = sheet('tblRemittance');
  int remittanceBlankRows = 0;
  if (remittanceSheet != null) {
    for (var r = 1; r < remittanceSheet.maxRows; r++) {
      final row = remittanceSheet.row(r);
      final legacyId = _asInt(_cell(row, 0));
      final productName = _asText(_cell(row, 2));
      if (legacyId == null || productName == null) {
        remittanceBlankRows++;
        continue;
      }
      batches.add(
        ParsedBatch(
          legacyId: legacyId,
          date: _asDate(_cell(row, 1)),
          productName: productName,
          count: _asDouble(_cell(row, 3)),
          price: _asDouble(_cell(row, 4)),
          remitted: _asBool(_cell(row, 6)),
          dateRemitted: _asDate(_cell(row, 7)),
        ),
      );
    }
  }
  if (remittanceBlankRows > 0) {
    report.add(
      ImportIssueCategory.blankRowsSkipped,
      '$remittanceBlankRows blank row(s) skipped in tblRemittance',
    );
  }

  final sales = <ParsedSale>[];
  final transactionSheet = sheet('tblTransactions');
  int transactionBlankRows = 0;
  if (transactionSheet != null) {
    for (var r = 1; r < transactionSheet.maxRows; r++) {
      final row = transactionSheet.row(r);
      final legacyId = _asInt(_cell(row, 0));
      final batchLegacyId = _asInt(_cell(row, 1));
      final customerName = _asText(_cell(row, 4));
      if (legacyId == null || batchLegacyId == null || customerName == null) {
        transactionBlankRows++;
        continue;
      }
      sales.add(
        ParsedSale(
          legacyId: legacyId,
          batchLegacyId: batchLegacyId,
          date: _asDate(_cell(row, 2)),
          customerName: customerName,
          amount: _asDouble(_cell(row, 5)),
          paid: _asBool(_cell(row, 6)),
          datePaid: _asDate(_cell(row, 7)),
        ),
      );
    }
  }
  if (transactionBlankRows > 0) {
    report.add(
      ImportIssueCategory.blankRowsSkipped,
      '$transactionBlankRows blank row(s) skipped in tblTransactions',
    );
  }

  return ParsedWorkbook(
    products: products,
    customers: customers,
    batches: batches,
    sales: sales,
  );
}
