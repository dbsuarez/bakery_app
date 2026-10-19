import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bakery_app/import/backup_restore_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes media-inclusive backup archives', () {
    final json = utf8.encode('{"version":2}');
    final image = <int>[1, 2, 3, 4];
    final archive = Archive()
      ..addFile(ArchiveFile('backup.json', json.length, json))
      ..addFile(
        ArchiveFile(
          'media/product-photos/photo.jpg',
          image.length,
          image,
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

    final payload = decodeBackupPayload(bytes);

    expect(utf8.decode(payload.jsonBytes), '{"version":2}');
    expect(payload.media['product-photos/photo.jpg'], image);
  });

  test('keeps existing JSON backups compatible', () {
    final bytes = Uint8List.fromList(utf8.encode('{"version":2}'));
    final payload = decodeBackupPayload(bytes);

    expect(payload.jsonBytes, bytes);
    expect(payload.media, isEmpty);
  });

  test('rejects an archive without backup.json', () {
    final archive = Archive()
      ..addFile(ArchiveFile('media/qr-codes/qr.jpg', 1, [1]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);

    expect(() => decodeBackupPayload(bytes), throwsFormatException);
  });
}
