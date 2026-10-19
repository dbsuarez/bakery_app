class RestoreIssue {
  final String message;
  const RestoreIssue(this.message);
}

/// Mirrors [ImportReport]'s shape so the Restore screen can reuse the same
/// summary/issues UI pattern as the spreadsheet importer.
class RestoreReport {
  RestoreReport();

  int productsCreated = 0;
  int productsUpdated = 0;
  int productsUnchanged = 0;
  int customersCreated = 0;
  int customersUpdated = 0;
  int customersUnchanged = 0;
  int batchesCreated = 0;
  int batchesUpdated = 0;
  int batchesUnchanged = 0;
  int salesCreated = 0;
  int salesUpdated = 0;
  int salesUnchanged = 0;

  final List<RestoreIssue> issues = [];

  factory RestoreReport.fromJson(Map<String, dynamic> json) {
    final report = RestoreReport()
      ..productsCreated = json['products_created'] as int? ?? 0
      ..productsUpdated = json['products_updated'] as int? ?? 0
      ..customersCreated = json['customers_created'] as int? ?? 0
      ..customersUpdated = json['customers_updated'] as int? ?? 0
      ..batchesCreated = json['batches_created'] as int? ?? 0
      ..batchesUpdated = json['batches_updated'] as int? ?? 0
      ..salesCreated = json['sales_created'] as int? ?? 0
      ..salesUpdated = json['sales_updated'] as int? ?? 0;
    final restored = json['dependent_rows_restored'] as int? ?? 0;
    if (restored > 0) {
      report.add(
        '$restored payment, credit, loyalty, expense, or preference rows restored.',
      );
    }
    return report;
  }

  void add(String message) => issues.add(RestoreIssue(message));
}
