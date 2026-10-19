import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../products/product_photo_service.dart';
import '../widgets/fullscreen_image_viewer.dart';

class MediaManagerScreen extends StatefulWidget {
  const MediaManagerScreen({super.key});

  @override
  State<MediaManagerScreen> createState() => _MediaManagerScreenState();
}

class _MediaManagerScreenState extends State<MediaManagerScreen> {
  Future<List<ProductPhotoFile>>? _future;
  final Set<String> _selected = {};
  bool _uploading = false;
  int _uploadTotal = 0;
  int _uploadDone = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _selected.clear();
      _future = listProductPhotos();
    });
  }

  Future<void> _uploadMany(BuildContext context) async {
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 82,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (picked.isEmpty || !context.mounted) return;

    setState(() {
      _uploading = true;
      _uploadTotal = picked.length;
      _uploadDone = 0;
    });

    var failures = 0;
    for (final file in picked) {
      try {
        await uploadStandaloneProductPhoto(file);
      } catch (_) {
        failures++;
      }
      if (mounted) setState(() => _uploadDone++);
    }

    if (!context.mounted) return;
    setState(() => _uploading = false);
    _load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failures == 0
              ? 'Uploaded ${picked.length} image(s).'
              : 'Uploaded ${picked.length - failures} of ${picked.length} image(s) - $failures failed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final usedUrls = appState.products
        .where((p) => p.imageUrl != null)
        .map((p) => stripCacheBust(p.imageUrl!))
        .toSet();
    final usedByUrl = {
      for (final p in appState.products)
        if (p.imageUrl != null) stripCacheBust(p.imageUrl!): p.title,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: 'Upload images',
            onPressed: _uploading ? null : () => _uploadMany(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
        bottom: _uploading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  value: _uploadTotal == 0 ? null : _uploadDone / _uploadTotal,
                ),
              )
            : null,
      ),
      body: FutureBuilder<List<ProductPhotoFile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load images: ${snapshot.error}'),
            );
          }
          final files = snapshot.data ?? [];
          if (files.isEmpty) {
            return const Center(child: Text('No images uploaded yet.'));
          }
          final unused = files
              .where((f) => !usedUrls.contains(stripCacheBust(f.publicUrl)))
              .toList();
          final used = files
              .where((f) => usedUrls.contains(stripCacheBust(f.publicUrl)))
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Unused (${unused.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (unused.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        if (_selected.length == unused.length) {
                          _selected.clear();
                        } else {
                          _selected
                            ..clear()
                            ..addAll(unused.map((f) => f.path));
                        }
                      }),
                      child: Text(
                        _selected.length == unused.length
                            ? 'Deselect all'
                            : 'Select all',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (unused.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Nothing to clean up - every image is in use.'),
                )
              else
                _PhotoGrid(
                  files: unused,
                  selectable: true,
                  selected: _selected,
                  onToggle: (path) => setState(() {
                    if (!_selected.remove(path)) _selected.add(path);
                  }),
                  onPreview: (index) => showFullscreenImageGallery(
                    context,
                    imageUrls: unused.map((f) => f.publicUrl).toList(),
                    initialIndex: index,
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'In use (${used.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              _PhotoGrid(
                files: used,
                selectable: false,
                selected: const {},
                labelForPath: (path, url) => usedByUrl[stripCacheBust(url)],
                onToggle: (_) {},
                onUsedTap: (path, url) {
                  final product = usedByUrl[stripCacheBust(url)];
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        product == null
                            ? 'This image is in use and can\'t be deleted.'
                            : 'This image is used by "$product" - remove or change '
                                  'that product\'s photo first if you want to delete it.',
                      ),
                    ),
                  );
                },
                onPreview: (index) => showFullscreenImageGallery(
                  context,
                  imageUrls: used.map((f) => f.publicUrl).toList(),
                  titles: used
                      .map((f) => usedByUrl[stripCacheBust(f.publicUrl)])
                      .toList(),
                  initialIndex: index,
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _deleteSelected(context),
                  icon: const Icon(Icons.delete_outline),
                  label: Text('Delete ${_selected.length} unused image(s)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete images?'),
        content: Text(
          'This permanently deletes ${_selected.length} image(s) from storage. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Re-check against the latest product list right before deleting - a
    // path selected a moment ago could have just been linked to a product
    // from another device.
    final freshUsedUrls = context
        .read<AppState>()
        .products
        .where((p) => p.imageUrl != null)
        .map((p) => stripCacheBust(p.imageUrl!))
        .toSet();
    final toDelete = _selected
        .where(
          (path) =>
              !freshUsedUrls.contains(stripCacheBust(publicUrlForPath(path))),
        )
        .toList();
    final skipped = _selected.length - toDelete.length;

    try {
      if (toDelete.isNotEmpty) await deleteProductPhotos(toDelete);
      _load();
      if (skipped > 0 && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$skipped image(s) skipped - they became linked to a product just now.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

class _PhotoGrid extends StatelessWidget {
  final List<ProductPhotoFile> files;
  final bool selectable;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String? Function(String path, String url)? labelForPath;
  final void Function(String path, String url)? onUsedTap;
  final ValueChanged<int>? onPreview;
  const _PhotoGrid({
    required this.files,
    required this.selectable,
    required this.selected,
    required this.onToggle,
    this.labelForPath,
    this.onUsedTap,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isSelected = selected.contains(file.path);
        final label = labelForPath?.call(file.path, file.publicUrl);
        return GestureDetector(
          onTap: selectable
              ? () => onToggle(file.path)
              : (onUsedTap == null
                    ? null
                    : () => onUsedTap!(file.path, file.publicUrl)),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: productThumbnailUrl(
                          file.publicUrl,
                          height: 400,
                        ),
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                    if (selectable)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: isSelected
                                ? Colors.greenAccent
                                : Colors.white,
                          ),
                        ),
                      )
                    else
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (onPreview != null)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Material(
                          color: Colors.black45,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => onPreview!(index),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.zoom_in,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (label != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
