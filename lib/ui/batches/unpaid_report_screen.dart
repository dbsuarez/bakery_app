import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';

import '../../analytics/customer_calculations.dart';
import '../../app_state.dart';
import '../../models/batch.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../reports/unpaid_report_pdf.dart' as report;
import '../../settings/business_settings_controller.dart';
import '../../theme/theme_controller.dart';
import '../../utils/app_date_format.dart';
import '../../utils/segment_label.dart';
import '../widgets/product_avatar.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

enum _CategoryFilter { all, bakery, merchandise }

class UnpaidReportScreen extends StatefulWidget {
  const UnpaidReportScreen({super.key});

  @override
  State<UnpaidReportScreen> createState() => _UnpaidReportScreenState();
}

class _UnpaidReportScreenState extends State<UnpaidReportScreen> {
  Set<int>? _selectedBatchIds;
  bool _batchesExpanded = false;
  bool _exporting = false;
  _CategoryFilter _filter = _CategoryFilter.all;

  List<Sale> _unpaidSalesFor(AppState appState) {
    return appState.sales
        .where((s) =>
            !s.isDeleted &&
            !s.paid &&
            s.saleType == SaleType.customerSale)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allUnpaid = _unpaidSalesFor(appState);

    final batchIdsWithUnpaid = allUnpaid.map((s) => s.batchId).toSet();
    final batches = appState.batches
        .where((b) => batchIdsWithUnpaid.contains(b.id))
        .toList()
      ..sort((a, b) => b.batchDate.compareTo(a.batchDate));

    // Default to every batch selected the first time this list is known.
    _selectedBatchIds ??= batchIdsWithUnpaid;

    final selectedUnpaid = allUnpaid
        .where((s) => _selectedBatchIds!.contains(s.batchId))
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
      ..sort((a, b) {
        final nameA = appState.customerById(a.customerId)?.name ?? '';
        final nameB = appState.customerById(b.customerId)?.name ?? '';
        final byName = nameA.toLowerCase().compareTo(nameB.toLowerCase());
        if (byName != 0) return byName;
        return a.saleDate.compareTo(b.saleDate);
      });

    final byCustomer = <int, List<Sale>>{};
    for (final s in selectedUnpaid) {
      byCustomer.putIfAbsent(s.customerId, () => []).add(s);
    }
    double remainingFor(Sale s) =>
        saleRemainingAmount(s, appState.salePayments);
    final total =
        selectedUnpaid.fold<double>(0, (sum, s) => sum + remainingFor(s));

    return Scaffold(
      appBar: AppBar(title: const Text('Unpaid Report')),
      body: batches.isEmpty
          ? const Center(child: Text('No unpaid transactions anywhere.'))
          : Column(
              children: [
                _BatchSelector(
                  batches: batches,
                  appState: appState,
                  allUnpaid: allUnpaid,
                  selected: _selectedBatchIds!,
                  expanded: _batchesExpanded,
                  onExpandedChanged: (v) =>
                      setState(() => _batchesExpanded = v),
                  onChanged: (ids) => setState(() => _selectedBatchIds = ids),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                const Divider(height: 1),
                Expanded(
                  child: selectedUnpaid.isEmpty
                      ? const Center(
                          child: Text('No unpaid transactions in the selected batches.'),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            for (final entry in byCustomer.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  appState.customerById(entry.key)?.name ??
                                      'Unknown customer',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              for (final s in entry.value)
                                ListTile(
                                  dense: true,
                                  leading: Builder(builder: (context) {
                                    final batch = appState.batchById(s.batchId);
                                    final product = batch == null
                                        ? null
                                        : appState.productById(batch.productId);
                                    return ProductAvatar(
                                        imageUrl: product?.imageUrl, radius: 16);
                                  }),
                                  title: Text(
                                    appState.batchById(s.batchId) != null
                                        ? appState
                                                .productById(appState
                                                        .batchById(s.batchId)!
                                                        .productId)
                                                ?.title ??
                                            ''
                                        : '',
                                  ),
                                  subtitle: Text(
                                    '${appDateFormat.format(s.saleDate)} · Qty ${s.quantity}',
                                  ),
                                  trailing: Text(_currency.format(remainingFor(s))),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'Subtotal: ${_currency.format(entry.value.fold<double>(0, (sum, s) => sum + remainingFor(s)))}',
                                    style: Theme.of(context).textTheme.labelMedium,
                                  ),
                                ),
                              ),
                              const Divider(height: 16),
                            ],
                          ],
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total unpaid: ${_currency.format(total)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: Colors.orange.shade800),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _exporting || selectedUnpaid.isEmpty
                              ? null
                              : () => _export(context, selectedUnpaid),
                          icon: _exporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Export PDF'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _export(BuildContext context, List<Sale> unpaidSales) async {
    setState(() => _exporting = true);
    try {
      final business = context.read<BusinessSettingsController>();
      final seedColor = context.read<ThemeController>().preset.seedColor;
      final appState = context.read<AppState>();
      await business.load();
      await report.shareUnpaidReport(
        appState,
        unpaidSales,
        businessName: business.name,
        brandColor: PdfColor.fromInt(seedColor.toARGB32()),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

class _BatchSelector extends StatelessWidget {
  final List<Batch> batches;
  final AppState appState;
  final List<Sale> allUnpaid;
  final Set<int> selected;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<Set<int>> onChanged;

  const _BatchSelector({
    required this.batches,
    required this.appState,
    required this.allUnpaid,
    required this.selected,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text('Batches (${selected.length}/${batches.length} selected)'),
        initiallyExpanded: expanded,
        onExpansionChanged: onExpandedChanged,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () =>
                      onChanged(batches.map((b) => b.id).toSet()),
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: () => onChanged({}),
                  child: const Text('Deselect all'),
                ),
              ],
            ),
          ),
          for (final b in batches)
            CheckboxListTile(
              dense: true,
              value: selected.contains(b.id),
              onChanged: (v) => onChanged(
                v == true
                    ? {...selected, b.id}
                    : (selected.where((id) => id != b.id).toSet()),
              ),
              secondary:
                  ProductAvatar(imageUrl: appState.productById(b.productId)?.imageUrl),
              title: Text(appState.productById(b.productId)?.title ?? '?'),
              subtitle: Text(
                '${appDateFormat.format(b.batchDate)} · '
                '${allUnpaid.where((s) => s.batchId == b.id).length} unpaid',
              ),
            ),
        ],
      ),
    );
  }
}
