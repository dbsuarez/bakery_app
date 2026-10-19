import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_state.dart';
import '../../import/backup_restore_service.dart';
import '../../import/restore_report.dart';

class RestoreScreen extends StatefulWidget {
  const RestoreScreen({super.key});

  @override
  State<RestoreScreen> createState() => _RestoreScreenState();
}

class _RestoreScreenState extends State<RestoreScreen> {
  bool _restoring = false;
  RestoreReport? _report;
  String? _error;

  Future<void> _pickAndRestore(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    if (!context.mounted) return;

    final bytes = result.files.single.bytes!;
    final service = BackupRestoreService(Supabase.instance.client);
    BackupRestorePreview preview;
    setState(() {
      _restoring = true;
      _error = null;
      _report = null;
    });
    try {
      preview = await service.preview(bytes);
    } catch (e) {
      if (mounted) {
        setState(() {
          _restoring = false;
          _error = '$e';
        });
      }
      return;
    }
    if (!context.mounted) return;
    setState(() => _restoring = false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from this backup?'),
        content: Text(
          'Validated ${preview.rowCount} rows from the backup made on '
          '${preview.exportedAt.toLocal()}.\n\n'
          '${preview.hasStaleConflicts ? '${preview.staleConflictCount} live row(s) are newer than this backup. Continuing will explicitly overwrite those newer values. ' : ''}'
          'Database restore is transactional: either every row succeeds or '
          'no database changes are saved. Media files are uploaded afterward '
          'and any individual upload failure is reported. Rows absent from '
          'the backup are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              preview.hasStaleConflicts
                  ? 'Overwrite newer data'
                  : 'Restore all rows',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    setState(() {
      _restoring = true;
      _error = null;
      _report = null;
    });

    try {
      final report = await service.restore(
        bytes,
        allowStaleOverwrite: preview.hasStaleConflicts,
      );
      if (!mounted) return;
      this.context.read<AppState>().refresh();
      setState(() => _report = report);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restore from Backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Restore a complete backup archive (.zip, including media) or a '
            'legacy version 2 JSON backup. The data is validated and '
            'previewed first, then restored in one database transaction. '
            'Incomplete version 1 backups are rejected.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _restoring ? null : () => _pickAndRestore(context),
            icon: _restoring
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.restore),
            label: Text(
              _restoring ? 'Restoring...' : 'Choose Backup .zip or .json',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_report != null) ...[
            const SizedBox(height: 24),
            _RestoreSummary(report: _report!),
            if (_report!.issues.isNotEmpty) ...[
              const SizedBox(height: 16),
              _RestoreIssues(report: _report!),
            ],
          ],
        ],
      ),
    );
  }
}

class _RestoreSummary extends StatelessWidget {
  final RestoreReport report;
  const _RestoreSummary({required this.report});

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
            Text(
              'Products: ${report.productsCreated} created, '
              '${report.productsUpdated} updated, '
              '${report.productsUnchanged} unchanged',
            ),
            Text(
              'Customers: ${report.customersCreated} created, '
              '${report.customersUpdated} updated, '
              '${report.customersUnchanged} unchanged',
            ),
            Text(
              'Batches: ${report.batchesCreated} created, '
              '${report.batchesUpdated} updated, '
              '${report.batchesUnchanged} unchanged',
            ),
            Text(
              'Transactions: ${report.salesCreated} created, '
              '${report.salesUpdated} updated, '
              '${report.salesUnchanged} unchanged',
            ),
            const SizedBox(height: 4),
            Text(
              '${report.issues.length} issue(s) flagged for review',
              style: TextStyle(
                color: report.issues.isEmpty
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreIssues extends StatelessWidget {
  final RestoreReport report;
  const _RestoreIssues({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text('Issues (${report.issues.length})'),
        children: [
          for (final issue in report.issues)
            ListTile(dense: true, title: Text(issue.message)),
        ],
      ),
    );
  }
}
