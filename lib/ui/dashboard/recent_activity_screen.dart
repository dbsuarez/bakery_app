import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/sale.dart';
import '../../repository/bakery_repository.dart';
import '../../utils/app_date_format.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

class RecentActivityScreen extends StatelessWidget {
  const RecentActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final activities = <_Activity>[
      for (final sale in state.sales.where((s) => !s.isDeleted))
        _Activity(
          sale.updatedAt,
          Icons.shopping_bag_outlined,
          'Transaction · ${state.customerById(sale.customerId)?.name ?? 'Unknown'}',
          _currency.format(sale.amount),
        ),
      for (final payment in state.salePayments.where((p) => !p.isDeleted))
        _Activity(
          payment.updatedAt,
          Icons.payments_outlined,
          'Payment received',
          _currency.format(payment.amount),
        ),
      for (final expense in state.expenses.where((e) => !e.isDeleted))
        _Activity(
          expense.updatedAt,
          Icons.receipt_long_outlined,
          'Expense · ${expense.category}',
          _currency.format(expense.amount),
        ),
      for (final batch in state.batches.where((b) => !b.isDeleted))
        _Activity(
          batch.updatedAt,
          Icons.inventory_2_outlined,
          'Batch · ${state.productById(batch.productId)?.title ?? 'Unknown'}',
          '${batch.countProduced} produced',
        ),
    ]..sort((a, b) => b.when.compareTo(a.when));

    final latestSale = state.sales
        .where((s) => !s.isDeleted)
        .fold<Sale?>(
          null,
          (latest, sale) =>
              latest == null || sale.updatedAt.isAfter(latest.updatedAt)
              ? sale
              : latest,
        );
    final latestBatch = latestSale == null
        ? null
        : state.batchById(latestSale.batchId);
    final canUndo =
        latestSale != null &&
        DateTime.now().difference(latestSale.updatedAt).inMinutes < 10 &&
        latestBatch != null &&
        !latestBatch.locked &&
        !latestBatch.remitted;

    return Scaffold(
      appBar: AppBar(title: const Text('Recent Activity')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (canUndo)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Undo latest transaction'),
                subtitle: Text(
                  '${state.customerById(latestSale.customerId)?.name ?? 'Customer'} · ${_currency.format(latestSale.amount)}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => _undoLatest(context, latestSale),
                  child: const Text('Undo'),
                ),
              ),
            ),
          if (activities.isEmpty)
            const Center(child: Text('No activity yet.'))
          else
            for (final activity in activities.take(50))
              ListTile(
                leading: Icon(activity.icon),
                title: Text(activity.title),
                subtitle: Text(
                  '${appDateFormat.format(activity.when)} · ${DateFormat.Hm().format(activity.when)}',
                ),
                trailing: Text(activity.detail),
              ),
        ],
      ),
    );
  }

  Future<void> _undoLatest(BuildContext context, Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Undo this transaction?'),
        content: const Text(
          'The latest transaction will be removed and its allocated quantity returned to the batch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Undo transaction'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<BakeryRepository>().deleteSale(sale.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Latest transaction undone.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not undo: $error')));
      }
    }
  }
}

class _Activity {
  final DateTime when;
  final IconData icon;
  final String title;
  final String detail;
  const _Activity(this.when, this.icon, this.title, this.detail);
}
