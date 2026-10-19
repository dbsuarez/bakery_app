import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';

import '../../analytics/customer_calculations.dart';
import '../../app_state.dart';
import '../../models/customer.dart';
import '../../reports/customer_statement_pdf.dart' as statement;
import '../../settings/business_settings_controller.dart';
import '../../theme/theme_controller.dart';
import '../../utils/money.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

/// Sentinel for the group filter meaning "no group assigned" - distinct
/// from `null`, which means "no filter, show every group".
const _ungroupedFilterValue = ' ungrouped';

/// Pick which customers (e.g. a household buying together) go into one
/// combined statement PDF - same per-customer layout and QR code as sharing
/// a single customer's statement, just bundled into one export.
class UnpaidStatementReportScreen extends StatefulWidget {
  const UnpaidStatementReportScreen({super.key});

  @override
  State<UnpaidStatementReportScreen> createState() =>
      _UnpaidStatementReportScreenState();
}

class _UnpaidStatementReportScreenState
    extends State<UnpaidStatementReportScreen> {
  String _search = '';
  String? _groupFilter;
  Set<int>? _selected;
  bool _exporting = false;
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

    final withBalance = appState.customers
        .where((c) =>
            !c.isArchived &&
            !c.isPseudoCustomer &&
            customerBalance(c.id, appState.sales, appState.salePayments) > 0)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // Default to every customer with a balance selected the first time.
    _selected ??= withBalance.map((c) => c.id).toSet();

    final visible = withBalance
        .where((c) => c.name.toLowerCase().contains(_search.toLowerCase()))
        .where((c) => switch (_groupFilter) {
              null => true,
              _ungroupedFilterValue => c.group == null,
              final g => c.group == g,
            })
        .toList();

    final selectedCustomers = withBalance
        .where((c) => _selected!.contains(c.id))
        .toList();
    final total = sumMoney(
      selectedCustomers.map(
        (c) => customerBalance(c.id, appState.sales, appState.salePayments),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Unpaid Statement Report')),
      body: withBalance.isEmpty
          ? const Center(child: Text('No customers with an outstanding balance.'))
          : Column(
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
                if (business.customerGroups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: const Text('All groups'),
                              selected: _groupFilter == null,
                              onSelected: (_) =>
                                  setState(() => _groupFilter = null),
                            ),
                          ),
                          for (final g in business.customerGroups)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(g),
                                selected: _groupFilter == g,
                                onSelected: (_) => setState(() =>
                                    _groupFilter = _groupFilter == g ? null : g),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: const Text('Ungrouped'),
                              selected: _groupFilter == _ungroupedFilterValue,
                              onSelected: (_) => setState(() => _groupFilter =
                                  _groupFilter == _ungroupedFilterValue
                                      ? null
                                      : _ungroupedFilterValue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                          '${_selected!.length}/${withBalance.length} selected'),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(
                            () => _selected = withBalance.map((c) => c.id).toSet()),
                        child: const Text('Select all'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selected = {}),
                        child: const Text('Deselect all'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final customer = visible[index];
                      final balance = customerBalance(
                          customer.id, appState.sales, appState.salePayments);
                      return CheckboxListTile(
                        value: _selected!.contains(customer.id),
                        onChanged: (v) => setState(() {
                          _selected = v == true
                              ? {..._selected!, customer.id}
                              : (_selected!.where((id) => id != customer.id).toSet());
                        }),
                        title: Text(customer.name),
                        secondary: CircleAvatar(
                          child: Text(customer.name.isNotEmpty
                              ? customer.name[0].toUpperCase()
                              : '?'),
                        ),
                        subtitle: Text(_currency.format(balance)),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total: ${_currency.format(total)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: Colors.orange.shade800),
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _exporting || selectedCustomers.isEmpty
                              ? null
                              : () => _export(context, selectedCustomers),
                          icon: _exporting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Share PDF'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _export(BuildContext context, List<Customer> customers) async {
    setState(() => _exporting = true);
    try {
      final business = context.read<BusinessSettingsController>();
      final seedColor = context.read<ThemeController>().preset.seedColor;
      final appState = context.read<AppState>();
      await business.load();
      await statement.shareBulkUnpaidStatements(
        appState,
        customers,
        businessName: business.name,
        enabledQrSlots: business.enabledQrSlots,
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
