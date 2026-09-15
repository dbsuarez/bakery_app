import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../analytics/payment_events.dart';
import '../../app_state.dart';
import '../../models/product.dart';
import '../../utils/app_date_format.dart';
import '../../utils/note_dialog.dart';
import '../../utils/segment_label.dart';
import '../widgets/product_avatar.dart';
import 'customer_ledger_screen.dart';
import 'payments_by_method_screen.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

enum _CategoryFilter { all, bakery, merchandise }

/// A chronological feed of every payment received - most recent first - a
/// running receipts log, distinct from the Unpaid Report which looks at
/// what's still owed. Each installment on a partial payment shows as its
/// own line, alongside sales paid off in one go.
class PaymentLogScreen extends StatefulWidget {
  const PaymentLogScreen({super.key});

  @override
  State<PaymentLogScreen> createState() => _PaymentLogScreenState();
}

class _PaymentLogScreenState extends State<PaymentLogScreen> {
  String _search = '';
  _CategoryFilter _filter = _CategoryFilter.all;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final payments =
        allPaymentEvents(appState.sales, appState.salePayments)
            .where((p) {
              if (_search.isEmpty) return true;
              final name = appState.customerById(p.customerId)?.name ?? '';
              return name.toLowerCase().contains(_search.toLowerCase());
            })
            .where((p) {
              if (_filter == _CategoryFilter.all) return true;
              final batch = appState.batchById(p.batchId);
              final category = batch == null
                  ? null
                  : appState.productById(batch.productId)?.category;
              return _filter == _CategoryFilter.bakery
                  ? category == ProductCategory.bakery
                  : category == ProductCategory.merchandise;
            })
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    final total = payments.fold<double>(0, (sum, p) => sum + p.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.pie_chart_outline),
            tooltip: 'By payment method',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaymentsByMethodScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search customers...',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search = '';
                          _searchController.clear();
                        }),
                      ),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<_CategoryFilter>(
                segments: [
                  ButtonSegment(
                    value: _CategoryFilter.all,
                    icon: const Icon(Icons.apps),
                    label: compactLabel('All'),
                    tooltip: 'All',
                  ),
                  ButtonSegment(
                    value: _CategoryFilter.bakery,
                    icon: const Icon(Icons.bakery_dining_outlined),
                    label: compactLabel('Bakery'),
                    tooltip: 'Bakery',
                  ),
                  ButtonSegment(
                    value: _CategoryFilter.merchandise,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: compactLabel('Merchandise'),
                    tooltip: 'Merchandise',
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${payments.length} payment(s) · Total: ${_currency.format(total)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: payments.isEmpty
                ? const Center(child: Text('No payments recorded yet.'))
                : ListView.builder(
                    itemCount: payments.length,
                    itemBuilder: (context, index) {
                      final payment = payments[index];
                      final customer = appState.customerById(
                        payment.customerId,
                      );
                      final batch = appState.batchById(payment.batchId);
                      final product = batch == null
                          ? null
                          : appState.productById(batch.productId);
                      return ListTile(
                        leading: ProductAvatar(imageUrl: product?.imageUrl),
                        title: Text(customer?.name ?? 'Unknown customer'),
                        subtitle: Text(
                          '${product?.title ?? ''} × ${payment.quantity} · '
                          'Paid ${appDateFormat.format(payment.date)}'
                          '${payment.paymentMethod != null ? ' via ${payment.paymentMethod}' : ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            NoteIndicator(note: payment.notes),
                            Text(_currency.format(payment.amount)),
                          ],
                        ),
                        onTap: customer == null
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CustomerLedgerScreen(
                                    customerId: customer.id,
                                  ),
                                ),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
