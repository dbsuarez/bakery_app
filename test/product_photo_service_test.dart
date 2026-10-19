import 'package:bakery_app/products/product_photo_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a Supabase thumbnail URL and preserves cache busting', () {
    final result = productThumbnailUrl(
      'https://project.supabase.co/storage/v1/object/public/'
      'product-photos/user/photo.png?t=123',
      width: 320,
      height: 180,
      quality: 75,
    );
    final uri = Uri.parse(result);

    expect(
      uri.path,
      '/storage/v1/render/image/public/product-photos/user/photo.png',
    );
    expect(uri.queryParameters['t'], '123');
    expect(uri.queryParameters['width'], '320');
    expect(uri.queryParameters['height'], '180');
    expect(uri.queryParameters['quality'], '75');
    expect(uri.queryParameters['resize'], 'cover');
  });

  test('leaves non-Supabase-storage URLs unchanged', () {
    const url = 'https://example.com/photo.jpg';
    expect(productThumbnailUrl(url), url);
  });
}
