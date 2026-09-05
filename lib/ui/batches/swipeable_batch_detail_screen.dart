import 'package:flutter/material.dart';

import 'batch_detail_screen.dart';

/// Wraps [BatchDetailScreen] in a horizontal pager over [batchIds] so a
/// user can swipe to the next/previous batch without backing out to the
/// list - each page is a full, independent instance of the detail screen.
class SwipeableBatchDetailScreen extends StatefulWidget {
  final List<int> batchIds;
  final int initialIndex;

  const SwipeableBatchDetailScreen({
    super.key,
    required this.batchIds,
    required this.initialIndex,
  });

  @override
  State<SwipeableBatchDetailScreen> createState() =>
      _SwipeableBatchDetailScreenState();
}

class _SwipeableBatchDetailScreenState
    extends State<SwipeableBatchDetailScreen> {
  late final _controller = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.batchIds.isEmpty) {
      return BatchDetailScreen(batchId: -1);
    }
    return PageView.builder(
      controller: _controller,
      itemCount: widget.batchIds.length,
      itemBuilder: (context, index) =>
          BatchDetailScreen(batchId: widget.batchIds[index]),
    );
  }
}
