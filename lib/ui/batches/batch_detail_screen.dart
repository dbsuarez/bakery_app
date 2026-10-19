import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../app_state.dart';
import '../../celebration/celebration_controller.dart';
import '../../models/sale.dart';
import '../../products/product_photo_service.dart';
import '../../repository/bakery_repository.dart';
import '../../settings/business_settings_controller.dart';
import '../../utils/app_date_format.dart';
import '../../utils/guarded_action.dart';
import '../batch_add_transactions/batch_add_transactions_screen.dart';
import '../widgets/fullscreen_image_viewer.dart';
import 'batch_form_screen.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

class BatchDetailScreen extends StatefulWidget {
  final int batchId;
  const BatchDetailScreen({super.key, required this.batchId});

  @override
  State<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<BatchDetailScreen> {
  bool _showCost = false;

  int get batchId => widget.batchId;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final batch = appState.batchById(batchId);
    if (batch == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Batch')),
        body: const Center(child: Text('Batch not found.')),
      );
    }
    final product = appState.productById(batch.productId);
    final sales =
        appState.sales
            .where((s) => s.batchId == batchId && !s.isDeleted)
            .toList()
          ..sort((a, b) {
            final aUnpaid = !a.paid && a.saleType.value == 'customer_sale';
            final bUnpaid = !b.paid && b.saleType.value == 'customer_sale';
            if (aUnpaid != bUnpaid) return aUnpaid ? -1 : 1;
            return b.saleDate.compareTo(a.saleDate);
          });
    final allocated = allocatedQuantity(batchId, appState.sales);
    final remaining = remainingQuantity(batch, appState.sales);

    return Scaffold(
      appBar: AppBar(
        title: Text(product?.title ?? 'Batch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Duplicate batch',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BatchFormScreen(duplicateFrom: batch),
              ),
            ),
          ),
          if (!batch.locked)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BatchFormScreen(batchId: batchId),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product?.imageUrl != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTap: () => showFullscreenImage(
                          context,
                          product.imageUrl!,
                          title: product.title,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: productThumbnailUrl(
                              product!.imageUrl!,
                              width: 640,
                              height: 280,
                            ),
                            height: 140,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              height: 140,
                              color: Colors.red.shade50,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 32,
                                color: Colors.red.shade400,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        appDateFormat.format(batch.batchDate),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (batch.isPersonal)
                        const Chip(
                          avatar: Icon(Icons.person, size: 16),
                          label: Text('Personal'),
                        ),
                      if (batch.remitted)
                        Chip(
                          avatar: const Icon(Icons.lock, size: 16),
                          label: Text(
                            'Remitted ${batch.dateRemitted != null ? appDateFormat.format(batch.dateRemitted!) : ''}',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _LabelValueRow(
                    'Unit price',
                    _currency.format(batch.unitPrice),
                  ),
                  Text(
                    'Produced: ${batch.countProduced} · '
                    'Allocated: $allocated · Remaining: $remaining',
                  ),
                  _LabelValueRow(
                    'Total value',
                    _currency.format(batch.totalValue),
                  ),
                  if (batch.unitCost > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cost details',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        IconButton(
                          icon: Icon(
                            _showCost ? Icons.visibility : Icons.visibility_off,
                            size: 18,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              setState(() => _showCost = !_showCost),
                        ),
                      ],
                    ),
                    if (_showCost) ...[
                      _LabelValueRow(
                        'Unit cost',
                        _currency.format(batch.unitCost),
                      ),
                      _LabelValueRow(
                        'Estimated profit',
                        _currency.format(batch.estimatedProfit),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!batch.locked)
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BatchAddTransactionsScreen(initialBatchId: batchId),
                    ),
                  ),
                  icon: const Icon(Icons.groups),
                  label: const Text('Batch Add Transactions'),
                ),
              if (!batch.remitted && !batch.isPersonal)
                OutlinedButton.icon(
                  onPressed: () => _markRemitted(context),
                  icon: const Icon(Icons.lock),
                  label: const Text('Mark Remitted'),
                ),
              if (batch.locked)
                OutlinedButton.icon(
                  onPressed: () => _unlock(context),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock'),
                ),
              if (batch.remitted && !batch.locked)
                OutlinedButton.icon(
                  onPressed: () => _lock(context),
                  icon: const Icon(Icons.lock),
                  label: const Text('Lock'),
                ),
              if (batch.remitted)
                TextButton.icon(
                  onPressed: () => _revertRemittance(context),
                  icon: const Icon(Icons.undo),
                  label: const Text('Revert Remittance'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Transactions', style: Theme.of(context).textTheme.titleMedium),
          if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No transactions yet.'),
            ),
          for (final sale in sales)
            ListTile(
              leading: sale.isReservation
                  ? Icon(
                      Icons.bookmark,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              title: Text(
                appState.customerById(sale.customerId)?.name ??
                    'Unknown customer',
              ),
              subtitle: Text(
                'Qty ${sale.quantity} · ${_currency.format(sale.amount)} · '
                '${appDateFormat.format(sale.saleDate)}',
              ),
              trailing: sale.saleType == SaleType.pointsRedemption
                  ? Chip(
                      label: const Text('Redeemed'),
                      backgroundColor: Colors.amber.withValues(alpha: 0.2),
                    )
                  : sale.saleType != SaleType.customerSale
                  ? Chip(
                      label: Text(
                        sale.saleType == SaleType.internalConsumption
                            ? 'Internal'
                            : 'Unsold',
                      ),
                      backgroundColor: Colors.deepPurple.withValues(
                        alpha: 0.15,
                      ),
                    )
                  : Chip(
                      label: Text(sale.paid ? 'Paid' : 'Unpaid'),
                      backgroundColor: sale.paid
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.15),
                    ),
              onTap: () => _editSale(context, sale),
            ),
        ],
      ),
    );
  }

  Future<void> _markRemitted(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark batch remitted?'),
        content: const Text(
          'This locks batch metadata (product, date, counts, price, cost) '
          'from further edits. Sale payment status remains editable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark Remitted'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runGuarded(context, () async {
      await context.read<BakeryRepository>().markBatchRemitted(batchId, picked);
      // Meaningful confetti (spec section 12): closing out a batch.
      if (context.mounted) {
        context.read<CelebrationController>().celebrate();
      }
    });
  }

  Future<void> _unlock(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlock batch?'),
        content: const Text('This allows editing batch metadata again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runGuarded(
      context,
      () => context.read<BakeryRepository>().unlockBatch(batchId),
    );
  }

  Future<void> _lock(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lock batch?'),
        content: const Text(
          'This blocks further edits to batch metadata and new customer '
          'sales, same as marking it remitted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Lock'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runGuarded(
      context,
      () => context.read<BakeryRepository>().lockBatch(batchId),
    );
  }

  Future<void> _revertRemittance(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revert remittance?'),
        content: const Text(
          'This clears the remitted status and date, and unlocks the batch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runGuarded(
      context,
      () => context.read<BakeryRepository>().revertBatchRemittance(batchId),
    );
  }

  Future<void> _editSale(BuildContext context, Sale sale) async {
    final quantityController = TextEditingController(
      text: sale.quantity.toString(),
    );
    final amountController = TextEditingController(
      text: sale.amount.toStringAsFixed(2),
    );
    final discountController = TextEditingController(
      text: sale.discount.toStringAsFixed(2),
    );
    var saleType = sale.saleType;
    var paid = sale.paid;
    var isReservation = sale.isReservation;
    final paymentMethods = context
        .read<BusinessSettingsController>()
        .paymentMethods;
    var paymentMethod =
        sale.paymentMethod ??
        (paymentMethods.isEmpty ? null : paymentMethods.first);

    final action = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<SaleType>(
                initialValue: saleType,
                decoration: const InputDecoration(labelText: 'Sale type'),
                items: const [
                  DropdownMenuItem(
                    value: SaleType.customerSale,
                    child: Text('Customer sale'),
                  ),
                  DropdownMenuItem(
                    value: SaleType.internalConsumption,
                    child: Text('Internal consumption (freebie/sample)'),
                  ),
                  DropdownMenuItem(
                    value: SaleType.pointsRedemption,
                    child: Text('Points redemption'),
                  ),
                ],
                onChanged: (v) => setDialogState(() => saleType = v!),
              ),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (saleType == SaleType.customerSale)
                TextField(
                  controller: discountController,
                  decoration: const InputDecoration(
                    labelText: 'Discount (optional)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              if (saleType == SaleType.customerSale)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reservation'),
                  value: isReservation,
                  onChanged: (v) => setDialogState(() => isReservation = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Paid'),
                value: paid,
                onChanged: (v) => setDialogState(() {
                  paid = v;
                  if (v && paymentMethod == null && paymentMethods.isNotEmpty) {
                    paymentMethod = paymentMethods.first;
                  }
                }),
              ),
              if (paid && paymentMethods.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: [
                    for (final m in paymentMethods)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => setDialogState(() => paymentMethod = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop('delete'),
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'delete') {
      final confirmDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this transaction?'),
          content: const Text(
            'This fully undoes it - its quantity goes back to the batch\'s '
            'available stock. This cannot be undone from the app.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmDelete == true && context.mounted) {
        await runGuarded(
          context,
          () => context.read<BakeryRepository>().deleteSale(sale.id),
        );
      }
      return;
    }

    final quantity = int.tryParse(quantityController.text);
    final amount = double.tryParse(amountController.text);
    if (quantity == null || quantity <= 0 || amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid quantity and amount')),
      );
      return;
    }
    final discount = saleType == SaleType.customerSale
        ? (double.tryParse(discountController.text) ?? 0)
        : 0.0;

    await runGuarded(
      context,
      () => context.read<BakeryRepository>().updateSale(
        Sale(
          id: sale.id,
          remoteId: sale.remoteId,
          legacyId: sale.legacyId,
          batchId: sale.batchId,
          customerId: sale.customerId,
          saleDate: sale.saleDate,
          quantity: quantity,
          amount: amount,
          discount: discount,
          paid: paid,
          datePaid: paid ? (sale.datePaid ?? DateTime.now()) : null,
          paymentMethod: paid ? paymentMethod : null,
          saleType: saleType,
          notes: sale.notes,
          isReservation: saleType == SaleType.customerSale && isReservation,
          updatedAt: DateTime.now(),
        ),
      ),
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  final String label;
  final String value;
  const _LabelValueRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text('$label:'), Text(value)],
    );
  }
}
