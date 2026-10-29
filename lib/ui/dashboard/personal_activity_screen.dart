import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/sale.dart';
import '../../utils/app_date_format.dart';
import '../batches/batch_detail_screen.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

/// Every sale entry recorded against a personal batch (`Batch.isPersonal`)
/// - the line items behind the "Personal units used" stat, since that
/// number alone doesn't say what was actually consumed or given away.
class PersonalActivityScreen extends StatelessWidget {
  const PersonalActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final personalBatchIds = appState.batches
        .where((b) => b.isPersonal && !b.isDeleted)
        .map((b) => b.id)
        .toSet();
    final entries =
        appState.sales
            .where((s) => !s.isDeleted && personalBatchIds.contains(s.batchId))
            .toList()
          ..sort((a, b) => b.saleDate.compareTo(a.saleDate));

    return Scaffold(
      appBar: AppBar(title: const Text('Personal activity')),
      body: entries.isEmpty
          ? const Center(child: Text('No personal batch activity yet.'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final sale = entries[index];
                final batch = appState.batchById(sale.batchId);
                final product = batch == null
                    ? null
                    : appState.productById(batch.productId);
                return ListTile(
                  title: Text(
                    '${product?.title ?? 'Unknown product'} × ${sale.quantity}',
                  ),
                  subtitle: Text(
                    '${appDateFormat.format(sale.saleDate)}'
                    '${sale.amount > 0 ? ' · ${_currency.format(sale.amount)}' : ''}',
                  ),
                  trailing: Chip(
                    label: Text(_typeLabel(sale.saleType)),
                    backgroundColor: Colors.deepPurple.withValues(alpha: 0.15),
                  ),
                  onTap: batch == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                BatchDetailScreen(batchId: batch.id),
                          ),
                        ),
                );
              },
            ),
    );
  }

  String _typeLabel(SaleType type) {
    switch (type) {
      case SaleType.internalConsumption:
        return 'Internal';
      case SaleType.unsold:
        return 'Unsold';
      case SaleType.customerSale:
        return 'Sold';
      case SaleType.pointsRedemption:
        return 'Redeemed';
    }
  }
}
