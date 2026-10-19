import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

class ImageOptimizationReport {
  final int optimized;
  final int skipped;
  final int failed;
  final int bytesBefore;
  final int bytesAfter;

  const ImageOptimizationReport({
    required this.optimized,
    required this.skipped,
    required this.failed,
    required this.bytesBefore,
    required this.bytesAfter,
  });

  int get bytesSaved => bytesBefore - bytesAfter;
}

class OptimizedImage {
  final Uint8List bytes;
  final bool changed;

  const OptimizedImage(this.bytes, this.changed);
}

/// Resizes without upscaling and keeps the original file format so persisted
/// public URLs remain valid after the storage object is overwritten.
OptimizedImage optimizeImageBytes({
  required Uint8List bytes,
  required String filename,
  required int maxDimension,
  required int jpegQuality,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return OptimizedImage(bytes, false);

  final longest = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final resized = longest > maxDimension
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
          interpolation: img.Interpolation.average,
        )
      : decoded;
  final extension = filename.split('.').last.toLowerCase();
  final Uint8List? encoded = switch (extension) {
    'jpg' || 'jpeg' => img.encodeJpg(resized, quality: jpegQuality),
    'png' => img.encodePng(resized, level: 6),
    _ => img.encodeNamedImage(filename, resized),
  };
  if (encoded == null || encoded.length >= bytes.length) {
    return OptimizedImage(bytes, false);
  }
  return OptimizedImage(encoded, true);
}

Future<ImageOptimizationReport> optimizeStoredImages() async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser!.id;
  var optimized = 0;
  var skipped = 0;
  var failed = 0;
  var bytesBefore = 0;
  var bytesAfter = 0;

  for (final config in const [
    (bucket: 'product-photos', maxDimension: 1600, quality: 82),
    (bucket: 'qr-codes', maxDimension: 2000, quality: 90),
  ]) {
    var offset = 0;
    const pageSize = 100;
    while (true) {
      final objects = await client.storage
          .from(config.bucket)
          .list(
            path: uid,
            searchOptions: SearchOptions(limit: pageSize, offset: offset),
          );
      for (final object in objects.where(
        (object) => object.name != '.emptyFolderPlaceholder',
      )) {
        final path = '$uid/${object.name}';
        try {
          final original = await client.storage
              .from(config.bucket)
              .download(path);
          final result = await compute(_optimizeInIsolate, (
            bytes: original,
            filename: object.name,
            maxDimension: config.maxDimension,
            quality: config.quality,
          ));
          if (!result.changed) {
            skipped++;
            continue;
          }
          await client.storage
              .from(config.bucket)
              .uploadBinary(
                path,
                result.bytes,
                fileOptions: const FileOptions(upsert: true),
              );
          optimized++;
          bytesBefore += original.length;
          bytesAfter += result.bytes.length;
        } catch (_) {
          failed++;
        }
      }
      if (objects.length < pageSize) break;
      offset += objects.length;
    }
  }

  return ImageOptimizationReport(
    optimized: optimized,
    skipped: skipped,
    failed: failed,
    bytesBefore: bytesBefore,
    bytesAfter: bytesAfter,
  );
}

OptimizedImage _optimizeInIsolate(
  ({Uint8List bytes, String filename, int maxDimension, int quality}) input,
) => optimizeImageBytes(
  bytes: input.bytes,
  filename: input.filename,
  maxDimension: input.maxDimension,
  jpegQuality: input.quality,
);
