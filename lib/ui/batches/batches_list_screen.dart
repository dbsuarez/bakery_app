import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../app_state.dart';
import '../../models/batch.dart';
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
    final remittanceTotal = sumMoney(
      batches.map((batch) => batchRevenue(batch.id, appState.sales)),
    );
    final selectionMode = _selectedBatchIds.isNotEmpty;
    final selectedBatches = appState.batches
        .where(
          (batch) =>
              _selectedBatchIds.contains(batch.id) && _isSelectable(batch),
        )
        .toList();
    final selectedTotal = sumMoney(
      selectedBatches.map((batch) => batchRevenue(batch.id, appState.sales)),
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
              _filter == BatchFilter.remitted)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _filter == BatchFilter.awaiting
                        ? 'Total to remit'
                        : 'Remitted total',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    _currency.format(remittanceTotal),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
                            : Text('₱${batch.totalValue.toStringAsFixed(2)}'),
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
