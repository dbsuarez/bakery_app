class RestoreIssue {
  final String message;
  const RestoreIssue(this.message);
}

/// Mirrors [ImportReport]'s shape so the Restore screen can reuse the same
/// summary/issues UI pattern as the spreadsheet importer.
class RestoreReport {
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

  void add(String message) => issues.add(RestoreIssue(message));
}
