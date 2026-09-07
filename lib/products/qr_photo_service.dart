import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'product_photo_service.dart' show cacheBust;

const _bucket = 'qr-codes';
const maxQrSlots = 3;

class QrPhotoFile {
  final int slot;
  final String path;
  final String publicUrl;
  const QrPhotoFile({
    required this.slot,
    required this.path,
    required this.publicUrl,
  });
}

/// Lists this user's uploaded payment QR images (up to [maxQrSlots]),
/// ordered by slot. A slot with nothing uploaded just doesn't appear.
Future<List<QrPhotoFile>> listQrPhotos() async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser!.id;
  final objects = await client.storage.from(_bucket).list(path: uid);
  final slotPattern = RegExp(r'^qr_(\d+)\.');
  final files = objects
      .where((o) => o.name != '.emptyFolderPlaceholder')
      .map((o) {
        final match = slotPattern.firstMatch(o.name);
        final slot = match == null ? 0 : int.tryParse(match.group(1)!) ?? 0;
        final path = '$uid/${o.name}';
        return QrPhotoFile(
          slot: slot,
          path: path,
          publicUrl: cacheBust(client.storage.from(_bucket).getPublicUrl(path)),
        );
      })
      .where((f) => f.slot > 0)
      .toList()
    ..sort((a, b) => a.slot.compareTo(b.slot));
  return files;
}

/// Uploads/replaces the QR image for [slot] (1-based, up to [maxQrSlots]).
/// Clears any previously-uploaded file for that slot first, in case it had
/// a different file extension, so it doesn't leave an orphaned duplicate.
Future<String> uploadQrImage({required int slot, required XFile file}) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser!.id;
  await deleteQrImage(slot);
  final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
  final path = '$uid/qr_$slot.$ext';
  final bytes = await file.readAsBytes();

  await client.storage.from(_bucket).uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(upsert: true),
      );

  return cacheBust(client.storage.from(_bucket).getPublicUrl(path));
}

/// Permanently removes whatever is uploaded for [slot], if anything.
Future<void> deleteQrImage(int slot) async {
  final existing = await listQrPhotos();
  final paths =
      existing.where((f) => f.slot == slot).map((f) => f.path).toList();
  if (paths.isNotEmpty) {
    await Supabase.instance.client.storage.from(_bucket).remove(paths);
  }
}
