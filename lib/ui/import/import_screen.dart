import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../import/import_report.dart';
import '../../import/import_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _importing = false;
  ImportReport? _report;
  String? _error;

  Future<void> _pickAndImport(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    if (!context.mounted) return;

    setState(() {
      _importing = true;
      _error = null;
      _report = null;
    });

    try {
      final report = await ImportService(Supabase.instance.client)
          .importWorkbook(result.files.single.bytes!);
      setState(() => _report = report);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Latest Spreadsheet')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Import products, customers, batches, and transactions from the '
            'legacy AR Spreadsheet (.xlsx). Safe to re-run: matching rows are '
            'updated, not duplicated, and issues are flagged for your review '
            'rather than silently corrected.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _importing ? null : () => _pickAndImport(context),
            icon: _importing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: Text(_importing ? 'Importing...' : 'Choose .xlsx File'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_report != null) ...[
            const SizedBox(height: 24),
            _ReportSummary(report: _report!),
            const SizedBox(height: 16),
            _ReportIssues(report: _report!),
          ],
        ],
      ),
    );
  }
}

class _ReportSummary extends StatelessWidget {
  final ImportReport report;
  const _ReportSummary({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Products created: ${report.productsCreated}'),
            Text('Customers created: ${report.customersCreated}'),
            Text('Batches: ${report.batchesCreated} created, '
                '${report.batchesUpdated} updated, '
                '${report.batchesUnchanged} unchanged'),
            Text('Transactions: ${report.salesCreated} created, '
                '${report.salesUpdated} updated, '
                '${report.salesUnchanged} unchanged'),
            const SizedBox(height: 4),
            Text('${report.issues.length} issue(s) flagged for review',
                style: TextStyle(
                  color: report.issues.isEmpty
                      ? Colors.green
                      : Theme.of(context).colorScheme.error,
                )),
          ],
        ),
      ),
    );
  }
}

class _ReportIssues extends StatelessWidget {
  final ImportReport report;
  const _ReportIssues({required this.report});

  String _label(ImportIssueCategory category) {
    switch (category) {
      case ImportIssueCategory.blankRowsSkipped:
        return 'Blank rows skipped';
      case ImportIssueCategory.missingId:
        return 'Missing IDs';
      case ImportIssueCategory.unknownReference:
        return 'Unknown references';
      case ImportIssueCategory.countPriceMismatch:
        return 'Count/price/total mismatches';
      case ImportIssueCategory.suspiciousInversion:
        return 'Suspicious count/price inversions';
      case ImportIssueCategory.batchAllocationMismatch:
        return 'Batch allocation mismatches';
      case ImportIssueCategory.duplicateCustomerName:
        return 'Duplicate customer names';
      case ImportIssueCategory.duplicateLegacyId:
        return 'Duplicate legacy IDs';
      case ImportIssueCategory.invalidDateOrAmount:
        return 'Invalid dates or amounts';
      case ImportIssueCategory.pseudoCustomerClassification:
        return 'Pseudo-customer classifications';
      case ImportIssueCategory.lockedBatchConflict:
        return 'Locked batch conflicts';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (report.issues.isEmpty) {
      return const Text('No issues found.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final category in ImportIssueCategory.values)
          if (report.forCategory(category).isNotEmpty)
            Card(
              child: ExpansionTile(
                title: Text(
                  '${_label(category)} (${report.forCategory(category).length})',
                ),
                children: [
                  for (final issue in report.forCategory(category))
                    ListTile(
                      dense: true,
                      title: Text(issue.message),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
