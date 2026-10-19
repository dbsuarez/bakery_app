import 'dart:typed_data';

import 'package:bakery_app/products/storage_image_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('shrinks an oversized image while preserving its filename format', () {
    final source = img.Image(width: 2400, height: 1200)
      ..clear(img.ColorRgb8(80, 40, 20));
    final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 100));

    final result = optimizeImageBytes(
      bytes: bytes,
      filename: 'photo.jpg',
      maxDimension: 1600,
      jpegQuality: 82,
    );
    final decoded = img.decodeJpg(result.bytes)!;

    expect(result.changed, isTrue);
    expect(decoded.width, 1600);
    expect(decoded.height, 800);
    expect(result.bytes.length, lessThan(bytes.length));
  });
}
