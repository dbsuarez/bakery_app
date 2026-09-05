import 'package:flutter/material.dart';

import 'customer_ledger_screen.dart';

/// Wraps [CustomerLedgerScreen] in a horizontal pager over [customerIds] so
/// a user can swipe to the next/previous customer without backing out to
/// the list - each page is a full, independent instance of the ledger.
class SwipeableCustomerLedgerScreen extends StatefulWidget {
  final List<int> customerIds;
  final int initialIndex;

  const SwipeableCustomerLedgerScreen({
    super.key,
    required this.customerIds,
    required this.initialIndex,
  });

  @override
  State<SwipeableCustomerLedgerScreen> createState() =>
      _SwipeableCustomerLedgerScreenState();
}

class _SwipeableCustomerLedgerScreenState
    extends State<SwipeableCustomerLedgerScreen> {
  late final _controller = PageController(initialPage: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.customerIds.isEmpty) {
      return CustomerLedgerScreen(customerId: -1);
    }
    return PageView.builder(
      controller: _controller,
      itemCount: widget.customerIds.length,
      itemBuilder: (context, index) =>
          CustomerLedgerScreen(customerId: widget.customerIds[index]),
    );
  }
}
