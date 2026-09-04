enum ImportIssueCategory {
  blankRowsSkipped,
  missingId,
  unknownReference,
  countPriceMismatch,
  suspiciousInversion,
  batchAllocationMismatch,
  duplicateCustomerName,
  duplicateLegacyId,
  invalidDateOrAmount,
  pseudoCustomerClassification,
  lockedBatchConflict,
}

class ImportIssue {
  final ImportIssueCategory category;
  final String message;
  const ImportIssue(this.category, this.message);
}

class ImportReport {
  int productsCreated = 0;
  int customersCreated = 0;
  int batchesCreated = 0;
  int batchesUpdated = 0;
  int batchesUnchanged = 0;
  int salesCreated = 0;
  int salesUpdated = 0;
  int salesUnchanged = 0;
  final List<ImportIssue> issues = [];

  void add(ImportIssueCategory category, String message) {
    issues.add(ImportIssue(category, message));
  }

  List<ImportIssue> forCategory(ImportIssueCategory category) =>
      issues.where((i) => i.category == category).toList();
}
