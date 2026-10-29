import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'restore_report.dart';

class BackupRestorePreview {
  final DateTime exportedAt;
  final int rowCount;
  final int staleConflictCount;

  const BackupRestorePreview({
    required this.exportedAt,
    required this.rowCount,
    required this.staleConflictCount,
  });

  bool get hasStaleConflicts => staleConflictCount > 0;
}

/// Validates backup v2 completely before asking PostgreSQL to restore it in
/// one transaction. Version 1 backups are intentionally rejected because
/// they omit financial ledgers and cannot produce a complete restore.
class BackupRestoreService {
  final SupabaseClient client;
  const BackupRestoreService(this.client);

  Future<BackupRestorePreview> preview(Uint8List bytes) async {
    final payload = decodeBackupPayload(bytes);
    final backup = decodeAndValidateBackupV2(payload.jsonBytes);
    final value = await client.rpc(
      'preview_backup_v2',
      params: {'p_backup': backup},
    );
    final result = Map<String, dynamic>.from(value as Map);
    return BackupRestorePreview(
      exportedAt: DateTime.parse(backup['exported_at'] as String),
      rowCount: result['row_count'] as int? ?? 0,
      staleConflictCount: result['stale_conflicts'] as int? ?? 0,
    );
  }

  Future<RestoreReport> restore(
    Uint8List bytes, {
    bool allowStaleOverwrite = false,
  }) async {
    final payload = decodeBackupPayload(bytes);
    final backup = decodeAndValidateBackupV2(payload.jsonBytes);
    final value = await client.rpc(
      'restore_backup_v2',
      params: {'p_backup': backup, 'p_allow_stale': allowStaleOverwrite},
    );
    final report = RestoreReport.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    if (backup.containsKey('cash_advances')) {
      await client.rpc(
        'restore_cash_advances_from_backup',
        params: {'p_backup': backup},
      );
    }
    if (payload.media.isNotEmpty) {
      final uid = client.auth.currentUser!.id;
      var restored = 0;
      for (final entry in payload.media.entries) {
        final separator = entry.key.indexOf('/');
        if (separator < 1) continue;
        final bucket = entry.key.substring(0, separator);
        final name = entry.key.substring(separator + 1);
        if (name.isEmpty || name.contains('..') || name.contains('\\')) {
          report.add('Skipped unsafe media path: media/${entry.key}');
          continue;
        }
        try {
          await client.storage
              .from(bucket)
              .uploadBinary(
                '$uid/$name',
                entry.value,
                fileOptions: const FileOptions(upsert: true),
              );
          restored++;
        } catch (error) {
          report.add('Could not restore media/$bucket/$name: $error');
        }
      }
      report.add('$restored of ${payload.media.length} media files restored.');
    }
    return report;
  }
}

class BackupPayload {
  final Uint8List jsonBytes;
  final Map<String, Uint8List> media;

  const BackupPayload({required this.jsonBytes, required this.media});
}

/// Accepts new media-inclusive ZIP archives and existing version 2 JSON files.
BackupPayload decodeBackupPayload(Uint8List bytes) {
  final isZip = bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
  if (!isZip) return BackupPayload(jsonBytes: bytes, media: const {});

  final archive = ZipDecoder().decodeBytes(bytes);
  Uint8List? jsonBytes;
  final media = <String, Uint8List>{};
  for (final file in archive.files.where((file) => file.isFile)) {
    final content = Uint8List.fromList(file.content as List<int>);
    if (file.name == 'backup.json') {
      jsonBytes = content;
    } else if (file.name.startsWith('media/')) {
      final relative = file.name.substring('media/'.length);
      if (relative.startsWith('product-photos/') ||
          relative.startsWith('qr-codes/')) {
        final separator = relative.indexOf('/');
        final name = separator < 0 ? '' : relative.substring(separator + 1);
        if (name.isNotEmpty && !name.contains('..') && !name.contains('\\')) {
          media[relative] = content;
        }
      }
    }
  }
  if (jsonBytes == null) {
    throw const FormatException('The backup archive is missing backup.json.');
  }
  return BackupPayload(jsonBytes: jsonBytes, media: media);
}

const _backupV2ListKeys = <String>[
  'products',
  'customers',
  'batches',
  'sales',
  'sale_payments',
  'customer_credits',
  'loyalty_adjustments',
  'expenses',
  'customer_favorites',
  'favorite_dismissals',
  'cash_advances',
  'cash_advance_payments',
];

/// Decodes and completely validates a backup before any network request or
/// database mutation is attempted.
Map<String, dynamic> decodeAndValidateBackupV2(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } catch (_) {
    throw const FormatException('The selected file is not valid JSON.');
  }
  if (decoded is! Map) {
    throw const FormatException('The backup root must be a JSON object.');
  }
  final backup = Map<String, dynamic>.from(decoded);
  if (backup['version'] != 2) {
    throw const FormatException(
      'Unsupported or incomplete backup version. Export a new version 2 '
      'backup before restoring.',
    );
  }
  // Cash advances were added without invalidating older complete v2 backups.
  backup.putIfAbsent('cash_advances', () => <dynamic>[]);
  backup.putIfAbsent('cash_advance_payments', () => <dynamic>[]);
  final exportedAt = backup['exported_at'];
  if (exportedAt is! String || DateTime.tryParse(exportedAt) == null) {
    throw const FormatException('The backup has an invalid export date.');
  }

  for (final key in _backupV2ListKeys) {
    final rows = backup[key];
    if (rows is! List) {
      throw FormatException('The backup is missing the "$key" list.');
    }
    for (var index = 0; index < rows.length; index++) {
      if (rows[index] is! Map) {
        throw FormatException('$key row ${index + 1} is not an object.');
      }
    }
  }

  final productIds = _entityIds(backup, 'products');
  final customerIds = _entityIds(backup, 'customers');
  final batchIds = _entityIds(backup, 'batches');
  final saleIds = _entityIds(backup, 'sales');
  final cashAdvanceIds = _entityIds(backup, 'cash_advances');
  _entityIds(backup, 'sale_payments');
  _entityIds(backup, 'customer_credits');
  _entityIds(backup, 'loyalty_adjustments');
  _entityIds(backup, 'expenses');

  _requireReferences(backup, 'batches', 'product_id', productIds);
  _requireReferences(backup, 'sales', 'batch_id', batchIds);
  _requireReferences(backup, 'sales', 'customer_id', customerIds);
  _requireReferences(backup, 'sale_payments', 'sale_id', saleIds);
  _requireReferences(backup, 'customer_credits', 'customer_id', customerIds);
  _requireOptionalReferences(backup, 'customer_credits', 'sale_id', saleIds);
  _requireReferences(backup, 'loyalty_adjustments', 'customer_id', customerIds);
  _requireReferences(backup, 'customer_favorites', 'customer_id', customerIds);
  _requireReferences(backup, 'customer_favorites', 'product_id', productIds);
  _requireReferences(backup, 'favorite_dismissals', 'customer_id', customerIds);
  _requireReferences(backup, 'favorite_dismissals', 'batch_id', batchIds);
  _requireReferences(backup, 'cash_advances', 'customer_id', customerIds);
  _requireReferences(
    backup,
    'cash_advance_payments',
    'cash_advance_id',
    cashAdvanceIds,
  );
  return backup;
}

Map<int, String> _entityIds(Map<String, dynamic> backup, String key) {
  final result = <int, String>{};
  for (final raw in backup[key] as List) {
    final row = Map<String, dynamic>.from(raw as Map);
    final localId = row['id'];
    final remoteId = row['remote_id'];
    if (localId is! int ||
        remoteId is! String ||
        !_uuidPattern.hasMatch(remoteId)) {
      throw FormatException(
        'Every $key row must have an integer id and valid remote_id.',
      );
    }
    if (result.containsKey(localId)) {
      throw FormatException('The backup contains duplicate $key ids.');
    }
    result[localId] = remoteId;
  }
  return result;
}

void _requireReferences(
  Map<String, dynamic> backup,
  String table,
  String field,
  Map<int, String> known,
) {
  for (final raw in backup[table] as List) {
    final value = (raw as Map)[field];
    if (value is! int || !known.containsKey(value)) {
      throw FormatException('$table contains an unknown $field reference.');
    }
  }
}

void _requireOptionalReferences(
  Map<String, dynamic> backup,
  String table,
  String field,
  Map<int, String> known,
) {
  for (final raw in backup[table] as List) {
    final value = (raw as Map)[field];
    if (value != null && (value is! int || !known.containsKey(value))) {
      throw FormatException('$table contains an unknown $field reference.');
    }
  }
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
