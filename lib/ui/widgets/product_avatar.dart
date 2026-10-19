import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../products/product_photo_service.dart';

/// A circular product-photo avatar that falls back to a bakery icon when
/// there's no photo, and to a distinct broken-image icon (instead of a
/// blank circle) when a photo URL exists but fails to load - e.g. the file
/// was deleted from the Media Manager while still linked to this product.
class ProductAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  const ProductAvatar({super.key, required this.imageUrl, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) {
      return CircleAvatar(
        radius: radius,
        child: Icon(Icons.bakery_dining_outlined, size: radius),
      );
    }
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: productThumbnailUrl(
            imageUrl!,
            width: radius <= 24 ? 128 : 320,
            height: radius <= 24 ? 128 : 320,
          ),
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              const ColoredBox(color: Colors.transparent),
          errorWidget: (context, url, error) => Container(
            color: Colors.red.shade50,
            alignment: Alignment.center,
            child: Icon(
              Icons.broken_image_outlined,
              size: radius,
              color: Colors.red.shade400,
            ),
          ),
        ),
      ),
    );
  }
}
