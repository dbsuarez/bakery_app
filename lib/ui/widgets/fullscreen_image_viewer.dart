import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Opens [imageUrl] full-screen over a dark backdrop, pinch-to-zoom and
/// pannable, dismissed by the back button/gesture or tapping the image.
/// [title], if given, is shown in the app bar (e.g. the product name).
void showFullscreenImage(
  BuildContext context,
  String imageUrl, {
  String? title,
}) {
  showFullscreenImageGallery(context, imageUrls: [imageUrl], titles: [title]);
}

/// Opens a horizontally swipeable full-screen gallery over [imageUrls],
/// starting at [initialIndex]. [titles], if given, must be the same length
/// as [imageUrls] and is shown per-page in the app bar.
void showFullscreenImageGallery(
  BuildContext context, {
  required List<String> imageUrls,
  List<String?>? titles,
  int initialIndex = 0,
}) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: _FullscreenImageGallery(
          imageUrls: imageUrls,
          titles: titles,
          initialIndex: initialIndex,
        ),
      ),
    ),
  );
}

class _FullscreenImageGallery extends StatefulWidget {
  final List<String> imageUrls;
  final List<String?>? titles;
  final int initialIndex;

  const _FullscreenImageGallery({
    required this.imageUrls,
    required this.titles,
    required this.initialIndex,
  });

  @override
  State<_FullscreenImageGallery> createState() =>
      _FullscreenImageGalleryState();
}

class _FullscreenImageGalleryState extends State<_FullscreenImageGallery> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.titles == null ? null : widget.titles![_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: title == null
            ? null
            : Text(title, style: const TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          if (widget.imageUrls.length > 1)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_index + 1}/${widget.imageUrls.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.imageUrls.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrls[i],
                fit: BoxFit.contain,
                errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image_outlined,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
