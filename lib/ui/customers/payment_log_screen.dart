import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../utils/app_date_format.dart';
import '../../utils/segment_label.dart';
import '../widgets/product_avatar.dart';
import 'customer_ledger_screen.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

enum _CategoryFilter { all, bakery, merchandise }

/// A chronological feed of every payment recorded (paid customer_sale rows,
/// most recent `date_paid` first) - a running receipts log, distinct from
/// the Unpaid Report which looks at what's still owed.
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
    final payments = appState.sales
        .where((s) =>
            !s.isDeleted &&
            s.paid &&
            s.datePaid != null &&
            s.saleType == SaleType.customerSale)
        .where((s) {
          if (_search.isEmpty) return true;
          final name = appState.customerById(s.customerId)?.name ?? '';
          return name.toLowerCase().contains(_search.toLowerCase());
        })
        .where((s) {
          if (_filter == _CategoryFilter.all) return true;
          final batch = appState.batchById(s.batchId);
          final category = batch == null
              ? null
              : appState.productById(batch.productId)?.category;
          return _filter == _CategoryFilter.bakery
              ? category == ProductCategory.bakery
              : category == ProductCategory.merchandise;
        })
        .toList()
      ..sort((a, b) => b.datePaid!.compareTo(a.datePaid!));

    final total = payments.fold<double>(0, (sum, s) => sum + s.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('Payment Log')),
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
                      final sale = payments[index];
                      final customer = appState.customerById(sale.customerId);
                      final batch = appState.batchById(sale.batchId);
                      final product =
                          batch == null ? null : appState.productById(batch.productId);
                      return ListTile(
                        leading: ProductAvatar(imageUrl: product?.imageUrl),
                        title: Text(customer?.name ?? 'Unknown customer'),
                        subtitle: Text(
                          '${product?.title ?? ''} × ${sale.quantity} · '
                          'Paid ${appDateFormat.format(sale.datePaid!)}'
                          '${sale.paymentMethod != null ? ' via ${sale.paymentMethod}' : ''}',
                        ),
                        trailing: Text(_currency.format(sale.amount)),
                        onTap: customer == null
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CustomerLedgerScreen(
                                        customerId: customer.id),
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
