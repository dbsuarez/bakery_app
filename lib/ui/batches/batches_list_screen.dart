import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../app_state.dart';
import '../../models/batch.dart';
import '../../models/sale.dart';
import '../../repository/bakery_repository.dart';
import '../../utils/app_date_format.dart';
import '../../utils/guarded_action.dart';
import '../../utils/money.dart';
import '../widgets/product_avatar.dart';
import 'batch_form_screen.dart';
import 'swipeable_batch_detail_screen.dart';
import 'unpaid_report_screen.dart';

enum BatchFilter { all, awaiting, remitted, personal }

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

class BatchesListScreen extends StatefulWidget {
  final String initialSearch;
  final BatchFilter initialFilter;

  const BatchesListScreen({
    super.key,
    this.initialSearch = '',
    this.initialFilter = BatchFilter.all,
  });

  @override
  State<BatchesListScreen> createState() => _BatchesListScreenState();
}

class _BatchesListScreenState extends State<BatchesListScreen> {
  late BatchFilter _filter = widget.initialFilter;
  late String _search = widget.initialSearch;
  late final _searchController = TextEditingController(text: _search);
  final Set<int> _selectedBatchIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static bool _matchesFilter(Batch batch, BatchFilter filter) {
    switch (filter) {
      case BatchFilter.all:
        return true;
      case BatchFilter.awaiting:
        return !batch.remitted && !batch.isPersonal;
      case BatchFilter.remitted:
        return batch.remitted;
      case BatchFilter.personal:
        return batch.isPersonal;
    }
  }

  bool _matches(Batch batch) => _matchesFilter(batch, _filter);

  static bool _isSelectable(Batch batch) =>
      !batch.remitted && !batch.isPersonal && !batch.isDeleted;

  Future<void> _showRemittanceDetails(
    BuildContext context,
    AppState appState,
    List<Batch> batches, {
    bool personal = false,
  }) async {
    final fullValue = sumMoney(batches.map((batch) => batch.totalValue));
    final internalValue = sumMoney(
      batches.map(
        (batch) => batchInternalConsumptionValue(batch, appState.sales),
      ),
    );
    final discountValue = sumMoney(
      batches.map((batch) => batchApprovedDiscountValue(batch, appState.sales)),
    );
    final addOnValue = sumMoney(
      batches.map((batch) => batchApprovedAddOnValue(batch, appState.sales)),
    );
    final adjustedValue = sumMoney(
      batches.map((batch) => batchRemittanceValue(batch, appState.sales)),
    );
    final recordedValue = sumMoney(
      batches.map(
        (batch) => batchRecordedCustomerTransactions(batch.id, appState.sales),
      ),
    );
    final difference = subtractMoney(adjustedValue, recordedValue);
    var soldQuantity = 0;
    var unsoldQuantity = 0;
    var unsoldValue = 0.0;
    for (final batch in batches) {
      soldQuantity += appState.sales
          .where(
            (sale) =>
                sale.batchId == batch.id &&
                !sale.isDeleted &&
                sale.saleType == SaleType.customerSale,
          )
          .fold<int>(0, (sum, sale) => sum + sale.quantity);
      final remaining = remainingQuantity(batch, appState.sales);
      final safeRemaining = remaining < 0 ? 0 : remaining;
      unsoldQuantity += safeRemaining;
      unsoldValue = sumMoney([
        unsoldValue,
        fromCentavos(safeRemaining * toCentavos(batch.unitPrice)),
      ]);
    }
    final detailBatches = batches.where((batch) {
      final gap = subtractMoney(
        batchRemittanceValue(batch, appState.sales),
        batchRecordedCustomerTransactions(batch.id, appState.sales),
      );
      return personal ||
          toCentavos(gap) != 0 ||
          toCentavos(batchInternalConsumptionValue(batch, appState.sales)) !=
              0 ||
          toCentavos(batchApprovedDiscountValue(batch, appState.sales)) != 0 ||
          toCentavos(batchApprovedAddOnValue(batch, appState.sales)) != 0;
    }).toList();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.all(16),
        title: Text(personal ? 'Personal batch details' : 'Remittance details'),
        scrollable: true,
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                personal
                    ? 'Review what was consumed, sold, redeemed, adjusted, and still unaccounted for.'
                    : 'Review internal-use products, approved price adjustments, and '
                          'anything that does not reconcile. Open a batch to correct an entry.',
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _SummaryAmountRow(
                        label: 'Full batch value',
                        amount: fullValue,
                      ),
                      if (personal) ...[
                        const SizedBox(height: 4),
                        _SummaryCountRow(label: 'Sold', count: soldQuantity),
                        const SizedBox(height: 4),
                        _SummaryCountRow(
                          label: 'Total unsold',
                          count: unsoldQuantity,
                          value: unsoldValue,
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                        _SummaryAmountRow(
                          label: 'Total unsold amount',
                          amount: unsoldValue,
                        ),
                      ],
                      if (toCentavos(internalValue) != 0) ...[
                        const SizedBox(height: 4),
                        _SummaryAmountRow(
                          label: 'Less internal use',
                          amount: -internalValue,
                          muted: true,
                        ),
                      ],
                      if (toCentavos(discountValue) != 0) ...[
                        const SizedBox(height: 4),
                        _SummaryAmountRow(
                          label: 'Less approved discounts',
                          amount: -discountValue,
                          muted: true,
                        ),
                      ],
                      if (toCentavos(addOnValue) != 0) ...[
                        const SizedBox(height: 4),
                        _SummaryAmountRow(
                          label: 'Plus approved add-ons',
                          amount: addOnValue,
                          muted: true,
                        ),
                      ],
                      const Divider(height: 20),
                      _SummaryAmountRow(
                        label: personal
                            ? 'Adjusted batch value'
                            : 'Amount to remit',
                        amount: adjustedValue,
                        emphasize: true,
                      ),
                      const SizedBox(height: 4),
                      _SummaryAmountRow(
                        label: 'Recorded customer transactions',
                        amount: recordedValue,
                      ),
                      if (toCentavos(difference) != 0) ...[
                        const SizedBox(height: 4),
                        _SummaryAmountRow(
                          label: personal
                              ? 'Unaccounted difference'
                              : 'Remittance gap',
                          amount: difference,
                          muted: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (detailBatches.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Everything reconciles'),
                    subtitle: Text('No remittance differences were found.'),
                  ),
                ),
              for (final batch in detailBatches)
                _RemittanceGapCard(
                  batch: batch,
                  sales: appState.sales
                      .where(
                        (sale) => sale.batchId == batch.id && !sale.isDeleted,
                      )
                      .toList(),
                  productName:
                      appState.productById(batch.productId)?.title ??
                      'Unknown product',
                  customerName: (customerId) =>
                      appState.customerById(customerId)?.name ??
                      'Unknown customer',
                  personal: personal,
                  onOpenBatch: () {
                    Navigator.of(dialogContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SwipeableBatchDetailScreen(
                          batchIds: [batch.id],
                          initialIndex: 0,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _toggleSelection(Batch batch) {
    if (!_isSelectable(batch)) return;
    setState(() {
      if (!_selectedBatchIds.add(batch.id)) {
        _selectedBatchIds.remove(batch.id);
      }
    });
  }

  Future<void> _markSelectedRemitted(
    BuildContext context,
    List<Batch> selectedBatches,
  ) async {
    if (selectedBatches.isEmpty) return;

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
        title: Text(
          'Mark ${selectedBatches.length} '
          '${selectedBatches.length == 1 ? 'batch' : 'batches'} remitted?',
        ),
        content: Text(
          'Remittance date: ${appDateFormat.format(picked)}\n\n'
          'This locks the selected batch metadata from further edits. '
          'Sale payment status remains editable.',
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

    var succeeded = false;
    await runGuarded(context, () async {
      final repository = context.read<BakeryRepository>();
      for (final batch in selectedBatches) {
        await repository.markBatchRemitted(batch.id, picked);
      }
      succeeded = true;
    });
    if (succeeded && context.mounted) {
      setState(_selectedBatchIds.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${selectedBatches.length} '
            '${selectedBatches.length == 1 ? 'batch' : 'batches'} marked remitted',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final searched = appState.batches
        .where(
          (b) =>
              appState
                  .productById(b.productId)
                  ?.title
                  .toLowerCase()
                  .contains(_search.toLowerCase()) ??
              _search.isEmpty,
        )
        .toList();
    final counts = {
      for (final f in BatchFilter.values)
        f: searched.where((b) => _matchesFilter(b, f)).length,
    };
    final batches = searched.where(_matches).toList()
      ..sort((a, b) {
        final dateCompare = b.batchDate.compareTo(a.batchDate);
        if (dateCompare != 0) return dateCompare;
        final aTitle = appState.productById(a.productId)?.title ?? '';
        final bTitle = appState.productById(b.productId)?.title ?? '';
        return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
      });
    final fullBatchValue = sumMoney(batches.map((batch) => batch.totalValue));
    final totalToRemit = sumMoney(
      batches.map((batch) => batchRemittanceValue(batch, appState.sales)),
    );
    final selectionMode = _selectedBatchIds.isNotEmpty;
    final selectedBatches = appState.batches
        .where(
          (batch) =>
              _selectedBatchIds.contains(batch.id) && _isSelectable(batch),
        )
        .toList();
    final selectedTotal = sumMoney(
      selectedBatches.map(
        (batch) => batchRemittanceValue(batch, appState.sales),
      ),
    );
    final visibleSelectableIds = batches
        .where(_isSelectable)
        .map((batch) => batch.id)
        .toSet();
    final allVisibleSelected =
        visibleSelectableIds.isNotEmpty &&
        visibleSelectableIds.every(_selectedBatchIds.contains);

    return Scaffold(
      appBar: AppBar(
        leading: selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Exit selection',
                onPressed: () => setState(_selectedBatchIds.clear),
              )
            : null,
        title: Text(
          selectionMode ? '${_selectedBatchIds.length} selected' : 'Batches',
        ),
        actions: selectionMode
            ? [
                IconButton(
                  icon: Icon(
                    allVisibleSelected ? Icons.deselect : Icons.select_all,
                  ),
                  tooltip: allVisibleSelected
                      ? 'Deselect visible batches'
                      : 'Select all visible batches',
                  onPressed: visibleSelectableIds.isEmpty
                      ? null
                      : () => setState(() {
                          if (allVisibleSelected) {
                            _selectedBatchIds.removeAll(visibleSelectableIds);
                          } else {
                            _selectedBatchIds.addAll(visibleSelectableIds);
                          }
                        }),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.receipt_long_outlined),
                  tooltip: 'Unpaid report',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const UnpaidReportScreen(),
                    ),
                  ),
                ),
              ],
      ),
      floatingActionButton: selectionMode
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BatchFormScreen()),
              ),
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: selectionMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: selectedBatches.isEmpty
                      ? null
                      : () => _markSelectedRemitted(context, selectedBatches),
                  icon: const Icon(Icons.lock_outline),
                  label: Text(
                    'Mark remitted · ${_currency.format(selectedTotal)}',
                  ),
                ),
              ),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search by product...',
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('All (${counts[BatchFilter.all]})'),
                  selected: _filter == BatchFilter.all,
                  onSelected: (_) => setState(() => _filter = BatchFilter.all),
                ),
                ChoiceChip(
                  label: Text(
                    'Awaiting Remittance (${counts[BatchFilter.awaiting]})',
                  ),
                  selected: _filter == BatchFilter.awaiting,
                  onSelected: (_) =>
                      setState(() => _filter = BatchFilter.awaiting),
                ),
                ChoiceChip(
                  label: Text('Remitted (${counts[BatchFilter.remitted]})'),
                  selected: _filter == BatchFilter.remitted,
                  onSelected: (_) =>
                      setState(() => _filter = BatchFilter.remitted),
                ),
                ChoiceChip(
                  label: Text('Personal (${counts[BatchFilter.personal]})'),
                  selected: _filter == BatchFilter.personal,
                  onSelected: (_) =>
                      setState(() => _filter = BatchFilter.personal),
                ),
              ],
            ),
          ),
          if (_filter == BatchFilter.awaiting ||
              _filter == BatchFilter.remitted ||
              _filter == BatchFilter.personal)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _SummaryAmountRow(
                    label: _filter == BatchFilter.awaiting
                        ? 'Total to remit'
                        : _filter == BatchFilter.personal
                        ? 'Personal batch value'
                        : 'Remitted total',
                    amount: _filter == BatchFilter.personal
                        ? fullBatchValue
                        : totalToRemit,
                    emphasize: true,
                    onAction:
                        _filter == BatchFilter.awaiting ||
                            _filter == BatchFilter.personal
                        ? () => _showRemittanceDetails(
                            context,
                            appState,
                            batches,
                            personal: _filter == BatchFilter.personal,
                          )
                        : null,
                    actionTooltip: 'View breakdown',
                  ),
                ],
              ),
            ),
          Expanded(
            child: batches.isEmpty
                ? _EmptyBatches(filter: _filter)
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: batches.length,
                    separatorBuilder: (_, _) => const Divider(indent: 72),
                    itemBuilder: (context, index) {
                      final batch = batches[index];
                      final product = appState.productById(batch.productId);
                      final remaining = remainingQuantity(
                        batch,
                        appState.sales,
                      );
                      final statusIcon = batch.isPersonal
                          ? Icons.person
                          : batch.remitted
                          ? Icons.lock
                          : Icons.lock_open;
                      final selectable = _isSelectable(batch);
                      final selected = _selectedBatchIds.contains(batch.id);
                      return ListTile(
                        selected: selected,
                        leading: selectionMode && selectable
                            ? Checkbox(
                                value: selected,
                                onChanged: (_) => _toggleSelection(batch),
                              )
                            : Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  ProductAvatar(imageUrl: product?.imageUrl),
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: CircleAvatar(
                                      radius: 9,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).scaffoldBackgroundColor,
                                      child: Icon(
                                        statusIcon,
                                        size: 11,
                                        color: batch.remitted
                                            ? Colors.grey
                                            : null,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                product?.title ?? 'Unknown product',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (batch.unitCost > 0) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.paid_outlined,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${appDateFormat.format(batch.batchDate)} · '
                          'Produced ${batch.countProduced} · Remaining $remaining',
                        ),
                        trailing: batch.isPersonal
                            ? const Text('Personal')
                            : batch.remitted
                            ? const Text('Remitted')
                            : Tooltip(
                                message: 'Batch value less internal use',
                                child: Text(
                                  _currency.format(
                                    batchRemittanceValue(batch, appState.sales),
                                  ),
                                ),
                              ),
                        onLongPress: selectable
                            ? () => setState(
                                () => _selectedBatchIds.add(batch.id),
                              )
                            : null,
                        onTap: () {
                          if (selectionMode) {
                            _toggleSelection(batch);
                            return;
                          }
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SwipeableBatchDetailScreen(
                                batchIds: batches.map((b) => b.id).toList(),
                                initialIndex: batches.indexOf(batch),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RemittanceGapCard extends StatelessWidget {
  final Batch batch;
  final List<Sale> sales;
  final String productName;
  final String Function(int customerId) customerName;
  final VoidCallback onOpenBatch;
  final bool personal;

  const _RemittanceGapCard({
    required this.batch,
    required this.sales,
    required this.productName,
    required this.customerName,
    required this.onOpenBatch,
    this.personal = false,
  });

  @override
  Widget build(BuildContext context) {
    final recorded = batchRecordedCustomerTransactions(batch.id, sales);
    final remit = batchRemittanceValue(batch, sales);
    final discounts = batchApprovedDiscountValue(batch, sales);
    final addOns = batchApprovedAddOnValue(batch, sales);
    final gap = subtractMoney(remit, recorded);
    final remaining = remainingQuantity(batch, sales);
    final soldQuantity = sales
        .where((sale) => sale.saleType == SaleType.customerSale)
        .fold<int>(0, (sum, sale) => sum + sale.quantity);
    final customerSales = sales.where(
      (sale) => sale.saleType == SaleType.customerSale,
    );
    final mismatches = customerSales.where((sale) {
      final expected = subtractMoney(
        fromCentavos(sale.quantity * toCentavos(batch.unitPrice)),
        sale.discount,
      );
      return toCentavos(subtractMoney(expected, sale.amount)) != 0;
    }).toList();
    final adjustedSales = customerSales
        .where((sale) => toCentavos(sale.discount) != 0)
        .toList();
    final redemptions = sales.where(
      (sale) => sale.saleType == SaleType.pointsRedemption,
    );
    final internalUseSales = sales.where(
      (sale) => sale.saleType == SaleType.internalConsumption,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(productName, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${appDateFormat.format(batch.batchDate)} · '
              'Produced ${batch.countProduced} · '
              '${personal ? 'Sold $soldQuantity · Unsold $remaining' : 'Remaining $remaining'}',
            ),
            const SizedBox(height: 10),
            _SummaryAmountRow(
              label: personal ? 'Adjusted batch value' : 'Amount to remit',
              amount: remit,
            ),
            if (toCentavos(discounts) != 0) ...[
              const SizedBox(height: 4),
              _SummaryAmountRow(
                label: 'Approved discounts deducted',
                amount: -discounts,
                muted: true,
              ),
            ],
            if (toCentavos(addOns) != 0) ...[
              const SizedBox(height: 4),
              _SummaryAmountRow(
                label: 'Approved add-ons included',
                amount: addOns,
                muted: true,
              ),
            ],
            const SizedBox(height: 4),
            _SummaryAmountRow(label: 'Customer transactions', amount: recorded),
            const SizedBox(height: 4),
            _SummaryAmountRow(
              label: personal ? 'Unaccounted difference' : 'Gap',
              amount: gap,
              emphasize: true,
            ),
            const Divider(height: 24),
            for (final sale in internalUseSales)
              _GapReason(
                icon: Icons.restaurant_outlined,
                title: 'Internal use · ${customerName(sale.customerId)}',
                detail: _internalUseText(batch, sale),
              ),
            if (remaining > 0)
              _GapReason(
                title:
                    '${personal ? 'Unsold' : 'Unassigned'}: $remaining '
                    '${remaining == 1 ? 'item' : 'items'}',
                detail: _currency.format(
                  fromCentavos(remaining * toCentavos(batch.unitPrice)),
                ),
              ),
            for (final sale in redemptions)
              _GapReason(
                title: '${customerName(sale.customerId)} redeemed with points',
                detail:
                    '${sale.quantity} Ã— ${_currency.format(batch.unitPrice)}',
              ),
            for (final sale in adjustedSales)
              _GapReason(
                icon: sale.discount > 0
                    ? Icons.discount_outlined
                    : Icons.add_circle_outline,
                title: sale.discount > 0
                    ? 'Approved discount · ${customerName(sale.customerId)}'
                    : 'Approved add-on · ${customerName(sale.customerId)}',
                detail: _adjustmentText(batch, sale),
              ),
            for (final sale in mismatches)
              _GapReason(
                title: customerName(sale.customerId),
                detail: _transactionMismatchText(batch, sale),
              ),
            if (toCentavos(gap) != 0 &&
                remaining == 0 &&
                redemptions.isEmpty &&
                mismatches.isEmpty)
              const Text(
                'The difference comes from the batch allocation. Open the batch '
                'to review all transactions.',
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: onOpenBatch,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Open and edit batch'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _transactionMismatchText(Batch batch, Sale sale) {
    final fullPrice = fromCentavos(sale.quantity * toCentavos(batch.unitPrice));
    final expected = subtractMoney(fullPrice, sale.discount);
    final difference = subtractMoney(expected, sale.amount);
    final direction = difference > 0 ? 'below' : 'above';
    final adjustment = sale.discount > 0
        ? ' (discount ${_currency.format(sale.discount)})'
        : sale.discount < 0
        ? ' (add-on ${_currency.format(-sale.discount)})'
        : '';
    return '${sale.quantity} Ã— ${_currency.format(batch.unitPrice)} = '
        '${_currency.format(fullPrice)}$adjustment; expected '
        '${_currency.format(expected)}, recorded ${_currency.format(sale.amount)}. '
        '${_currency.format(difference.abs())} $direction expected amount';
  }

  static String _internalUseText(Batch batch, Sale sale) {
    final value = fromCentavos(sale.quantity * toCentavos(batch.unitPrice));
    final note = sale.notes?.trim();
    return '${sale.quantity} × ${_currency.format(batch.unitPrice)} = '
        '${_currency.format(value)}${note == null || note.isEmpty ? '' : ' · $note'}';
  }

  static String _adjustmentText(Batch batch, Sale sale) {
    final fullPrice = fromCentavos(sale.quantity * toCentavos(batch.unitPrice));
    final signedAdjustment = -sale.discount;
    final sign = signedAdjustment >= 0 ? '+' : '−';
    final note = sale.notes?.trim();
    return '${sale.quantity} × ${_currency.format(batch.unitPrice)} = '
        '${_currency.format(fullPrice)} · $sign${_currency.format(signedAdjustment.abs())} '
        '· recorded ${_currency.format(sale.amount)}'
        '${note == null || note.isEmpty ? '' : ' · $note'}';
  }
}

class _GapReason extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _GapReason({
    this.icon = Icons.warning_amber_rounded,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(detail),
  );
}

class _SummaryAmountRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool emphasize;
  final bool muted;
  final VoidCallback? onAction;
  final String? actionTooltip;

  const _SummaryAmountRow({
    required this.label,
    required this.amount,
    this.emphasize = false,
    this.muted = false,
    this.onAction,
    this.actionTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final color = muted ? Theme.of(context).colorScheme.onSurfaceVariant : null;
    return Row(
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
        ),
        const Spacer(),
        Text(
          _currency.format(amount),
          style:
              (emphasize
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(
                    fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                    color: color,
                  ),
        ),
        if (onAction != null)
          IconButton(
            onPressed: onAction,
            tooltip: actionTooltip,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.receipt_long_outlined),
          ),
      ],
    );
  }
}

class _SummaryCountRow extends StatelessWidget {
  final String label;
  final int count;
  final double? value;

  const _SummaryCountRow({
    required this.label,
    required this.count,
    this.value,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelLarge),
      Text(
        value == null ? '$count' : '$count · ${_currency.format(value)}',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _EmptyBatches extends StatelessWidget {
  final BatchFilter filter;
  const _EmptyBatches({required this.filter});

  @override
  Widget build(BuildContext context) {
    final message = switch (filter) {
      BatchFilter.awaiting => 'No batches awaiting remittance',
      BatchFilter.remitted => 'No remitted batches',
      BatchFilter.personal => 'No personal batches',
      BatchFilter.all => 'No batches yet',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            if (filter == BatchFilter.all) ...[
              const SizedBox(height: 6),
              const Text('Tap + to add your first batch.'),
            ],
          ],
        ),
      ),
    );
  }
}
