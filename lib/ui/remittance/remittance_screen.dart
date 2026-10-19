import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../app_state.dart';
import '../../utils/app_date_format.dart';
import '../../utils/money.dart';
import '../batches/batch_detail_screen.dart';
import '../widgets/product_avatar.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

class RemittanceScreen extends StatelessWidget {
  const RemittanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final awaiting = appState.batches
        .where((b) => !b.remitted && !b.isDeleted && !b.isPersonal)
        .toList()
      ..sort((a, b) => b.batchDate.compareTo(a.batchDate));
    final remitted = appState.batches.where((b) => b.remitted && !b.isDeleted)
        .toList()
      ..sort((a, b) => b.dateRemitted!.compareTo(a.dateRemitted!));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Remittance'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Awaiting'),
            Tab(text: 'Remitted'),
          ]),
        ),
        body: TabBarView(
          children: [
            _BatchList(batches: awaiting, appState: appState, showRevenue: true),
            _BatchList(batches: remitted, appState: appState, showRevenue: false),
          ],
        ),
      ),
    );
  }
}

class _BatchList extends StatelessWidget {
  final List batches;
  final AppState appState;
  final bool showRevenue;
  const _BatchList(
      {required this.batches, required this.appState, required this.showRevenue});

  @override
  Widget build(BuildContext context) {
    final total = sumMoney(
      batches.map((b) => batchRevenue(b.id, appState.sales)),
    );
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${batches.length} batch${batches.length == 1 ? '' : 'es'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Total: ${_currency.format(total)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: batches.isEmpty
              ? const Center(child: Text('Nothing here.'))
              : ListView.builder(
                  itemCount: batches.length,
                  itemBuilder: (context, index) {
                    final batch = batches[index];
                    final product = appState.productById(batch.productId);
                    final revenue = batchRevenue(batch.id, appState.sales);
                    return ListTile(
                      leading: ProductAvatar(imageUrl: product?.imageUrl),
                      title: Text(product?.title ?? 'Unknown product'),
                      subtitle: Text(appDateFormat.format(batch.batchDate)),
                      trailing: Text(_currency.format(revenue)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BatchDetailScreen(batchId: batch.id),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
