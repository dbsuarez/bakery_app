import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../products/product_photo_service.dart';

/// Shows every image already uploaded to the product-photos bucket and lets
/// the user pick one to reuse on a different product, instead of uploading
/// a duplicate. Returns a fresh cache-busted URL for the picked file, or
/// null if the user backed out.
Future<String?> showBrowsePhotosDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Choose an existing image',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<List<ProductPhotoFile>>(
                future: listProductPhotos(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Could not load images: ${snapshot.error}'),
                    );
                  }
                  final files = snapshot.data ?? [];
                  if (files.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No images uploaded yet.'),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 110,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.of(context)
                            .pop(cacheBust(file.publicUrl)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: file.publicUrl,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
