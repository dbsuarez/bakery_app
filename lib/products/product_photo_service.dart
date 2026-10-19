import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

const _bucket = 'product-photos';
const _uuid = Uuid();

/// Uploads to the `product-photos` bucket at `<user_id>/<stable_id>.<ext>`
/// (see docs/supabase_bakery_database_setup.sql for the bucket + RLS) and
/// returns a cache-busted public URL. `stableId` should be the product's
/// Supabase UUID (`Product.remoteId`) - not the session-local int id - so
/// re-uploads overwrite the same object instead of orphaning old ones.
Future<String> uploadProductPhoto({
  required String stableId,
  required XFile file,
}) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser!.id;
  final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
  final path = '$uid/$stableId.$ext';
  final bytes = await file.readAsBytes();

  await client.storage
      .from(_bucket)
      .uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(upsert: true),
      );

  return cacheBust(client.storage.from(_bucket).getPublicUrl(path));
}

/// Uploads a file that isn't tied to any particular product yet - used by
/// the Media Manager's bulk upload, so photos can be prepared ahead of time
/// and assigned to products later via "Browse existing images". Stored at
/// `<user_id>/<random_uuid>.<ext>` so it never collides with a per-product
/// path and starts out "unused" until a product links to it.
Future<String> uploadStandaloneProductPhoto(XFile file) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser!.id;
  final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
  final path = '$uid/${_uuid.v4()}.$ext';
  final bytes = await file.readAsBytes();

  await client.storage
      .from(_bucket)
      .uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: const FileOptions(upsert: true),
      );

  return cacheBust(client.storage.from(_bucket).getPublicUrl(path));
}

/// Appends a fresh cache-busting query param so a just-changed image shows
/// immediately instead of the browser/CDN serving a stale cached copy.
String cacheBust(String publicUrl) =>
    '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';

/// Strips the `?t=...` cache-bust suffix so two URLs for the same underlying
/// storage object compare equal regardless of when each was generated.
String stripCacheBust(String url) => url.split('?').first;

/// Requests a small rendered copy for list/grid use while leaving the stored
/// original URL untouched for persistence and fullscreen viewing.
String productThumbnailUrl(
  String publicUrl, {
  int width = 400,
  int? height,
  int quality = 70,
}) {
  final uri = Uri.tryParse(publicUrl);
  const objectPrefix = '/storage/v1/object/public/';
  if (uri == null || !uri.path.contains(objectPrefix)) return publicUrl;
  return uri
      .replace(
        path: uri.path.replaceFirst(
          objectPrefix,
          '/storage/v1/render/image/public/',
        ),
        queryParameters: {
          ...uri.queryParameters,
          'width': '$width',
          if (height != null) 'height': '$height',
          'quality': '$quality',
          'resize': 'cover',
        },
      )
      .toString();
}

class ProductPhotoFile {
  final String path;
  final String publicUrl;
  final DateTime? updatedAt;
  const ProductPhotoFile({
    required this.path,
    required this.publicUrl,
    this.updatedAt,
  });
}

/// Lists every file this user has ever uploaded to the product-photos
/// bucket - including ones no product currently references, e.g. left
/// behind after a product was deleted or its photo was changed.
Future<List<ProductPhotoFile>> listProductPhotos() async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser!.id;
  final objects = await client.storage.from(_bucket).list(path: uid);
  return objects.where((o) => o.name != '.emptyFolderPlaceholder').map((o) {
    final path = '$uid/${o.name}';
    return ProductPhotoFile(
      path: path,
      publicUrl: client.storage.from(_bucket).getPublicUrl(path),
      updatedAt: o.updatedAt == null ? null : DateTime.tryParse(o.updatedAt!),
    );
  }).toList();
}

/// Permanently deletes the given storage paths (as returned by
/// [ProductPhotoFile.path]). Irreversible.
Future<void> deleteProductPhotos(List<String> paths) async {
  await Supabase.instance.client.storage.from(_bucket).remove(paths);
}

/// Reconstructs the public URL for a storage path without a network call -
/// used to re-check whether a path is still unused right before deleting.
String publicUrlForPath(String path) =>
    Supabase.instance.client.storage.from(_bucket).getPublicUrl(path);
