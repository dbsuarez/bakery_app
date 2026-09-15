import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../app_state.dart';
import '../../models/batch.dart';
import '../../utils/app_date_format.dart';
import '../widgets/product_avatar.dart';
import 'batch_form_screen.dart';
import 'swipeable_batch_detail_screen.dart';
import 'unpaid_report_screen.dart';

enum BatchFilter { all, awaiting, remitted, personal }

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batches'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Unpaid report',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UnpaidReportScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const BatchFormScreen())),
        child: const Icon(Icons.add),
      ),
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
          Expanded(
            child: batches.isEmpty
                ? const Center(child: Text('No batches here.'))
                : ListView.builder(
                    itemCount: batches.length,
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
                      return ListTile(
                        leading: Stack(
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
                                  color: batch.remitted ? Colors.grey : null,
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
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SwipeableBatchDetailScreen(
                              batchIds: batches.map((b) => b.id).toList(),
                              initialIndex: batches.indexOf(batch),
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
