import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/customer_calculations.dart';
import '../../app_state.dart';
import '../../models/product.dart';
import '../../settings/business_settings_controller.dart';
import '../../utils/segment_label.dart';
import 'customer_ledger_screen.dart';

class LoyaltyPointsScreen extends StatefulWidget {
  const LoyaltyPointsScreen({super.key});

  @override
  State<LoyaltyPointsScreen> createState() => _LoyaltyPointsScreenState();
}

enum _CategoryFilter { all, bakery, merchandise }

class _LoyaltyPointsScreenState extends State<LoyaltyPointsScreen> {
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
    final business = context.watch<BusinessSettingsController>();

    final entries = normalCustomers(appState.customers)
        .where((c) => c.name.toLowerCase().contains(_search.toLowerCase()))
        .map((c) => (
              customer: c,
              bakeryPoints: customerPointsBalance(
                c.id,
                appState.sales,
                appState.batches,
                appState.products,
                appState.loyaltyAdjustments,
                category: ProductCategory.bakery,
                pesosPerPoint: business.pesosPerPoint,
                sameDayBonusPercent: business.sameDayBonusPercent,
                redeemPesosPerPoint: business.redeemPesosPerPoint,
                sameDayBonusStartDate: business.sameDayBonusStartDate,
              ),
              merchandisePoints: customerPointsBalance(
                c.id,
                appState.sales,
                appState.batches,
                appState.products,
                appState.loyaltyAdjustments,
                category: ProductCategory.merchandise,
                pesosPerPoint: business.pesosPerPoint,
                sameDayBonusPercent: business.sameDayBonusPercent,
                redeemPesosPerPoint: business.redeemPesosPerPoint,
                sameDayBonusStartDate: business.sameDayBonusStartDate,
              ),
            ))
        .where((e) => switch (_filter) {
              _CategoryFilter.all => e.bakeryPoints > 0 || e.merchandisePoints > 0,
              _CategoryFilter.bakery => e.bakeryPoints > 0,
              _CategoryFilter.merchandise => e.merchandisePoints > 0,
            })
        .toList()
      ..sort((a, b) => switch (_filter) {
            _CategoryFilter.all => (b.bakeryPoints + b.merchandisePoints)
                .compareTo(a.bakeryPoints + a.merchandisePoints),
            _CategoryFilter.bakery =>
              b.bakeryPoints.compareTo(a.bakeryPoints),
            _CategoryFilter.merchandise =>
              b.merchandisePoints.compareTo(a.merchandisePoints),
          });

    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty Points')),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Earn: ₱${business.pesosPerPoint.toStringAsFixed(0)} = 1 point '
                '(+${business.sameDayBonusPercent.toStringAsFixed(0)}% same-day) · '
                'Redeem: 1 pt = ₱${business.redeemPesosPerPoint.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      switch (_filter) {
                        _CategoryFilter.all => 'No customers with points yet.',
                        _CategoryFilter.bakery =>
                          'No customers with bakery points yet.',
                        _CategoryFilter.merchandise =>
                          'No customers with merchandise points yet.',
                      },
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final e = entries[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            e.customer.name.isNotEmpty
                                ? e.customer.name[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(e.customer.name),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_filter != _CategoryFilter.merchandise &&
                                e.bakeryPoints > 0)
                              Text(
                                'Bakery: ${e.bakeryPoints} pts',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.amber.shade800),
                              ),
                            if (_filter != _CategoryFilter.bakery &&
                                e.merchandisePoints > 0)
                              Text(
                                'Merch: ${e.merchandisePoints} pts',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: Colors.amber.shade800),
                              ),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CustomerLedgerScreen(
                                customerId: e.customer.id),
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
