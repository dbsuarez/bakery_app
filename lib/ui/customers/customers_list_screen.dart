import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../analytics/customer_calculations.dart';
import '../../app_state.dart';
import '../../customer_portal/customer_portal_service.dart';
import '../../models/customer.dart';
import '../../models/sale.dart';
import '../../repository/bakery_repository.dart';
import '../../settings/business_settings_controller.dart';
import '../../utils/segment_label.dart';
import 'loyalty_points_screen.dart';
import 'payment_log_screen.dart';
import 'swipeable_customer_ledger_screen.dart';
import 'unpaid_statement_report_screen.dart';

class CustomersListScreen extends StatefulWidget {
  const CustomersListScreen({super.key});

  @override
  State<CustomersListScreen> createState() => _CustomersListScreenState();
}

enum _CustomerFilter { withBalance, all, archived }

enum _SoaLinkAction { copy, share }

/// Sentinel for the group filter meaning "no group assigned" - distinct
/// from `null`, which means "no filter, show every group".
const _ungroupedFilterValue = '__ungrouped__';

class _CustomersListScreenState extends State<CustomersListScreen> {
  String _search = '';
  _CustomerFilter _filter = _CustomerFilter.withBalance;
  String? _groupFilter;
  final _searchController = TextEditingController();
  final Set<int> _copyingSoaLinks = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final business = context.watch<BusinessSettingsController>();
    var customers = appState.customers
        .where((c) => c.name.toLowerCase().contains(_search.toLowerCase()))
        .where(
          (c) => switch (_groupFilter) {
            null => true,
            _ungroupedFilterValue => c.group == null,
            final g => c.group == g,
          },
        )
        .toList();
    if (_filter == _CustomerFilter.archived) {
      customers = customers.where((c) => c.isArchived).toList();
    } else {
      customers = customers.where((c) => !c.isArchived).toList();
      if (_filter == _CustomerFilter.withBalance) {
        customers = customers
            .where(
              (c) =>
                  customerBalance(
                    c.id,
                    appState.sales,
                    appState.salePayments,
                    appState.cashAdvances,
                    appState.cashAdvancePayments,
                  ) >
                  0,
            )
            .toList();
      }
    }
    // Customers with an outstanding balance surface first, alphabetical
    // within each group.
    customers.sort((a, b) {
      final aOwes =
          customerBalance(
            a.id,
            appState.sales,
            appState.salePayments,
            appState.cashAdvances,
            appState.cashAdvancePayments,
          ) >
          0;
      final bOwes =
          customerBalance(
            b.id,
            appState.sales,
            appState.salePayments,
            appState.cashAdvances,
            appState.cashAdvancePayments,
          ) >
          0;
      if (aOwes != bOwes) return aOwes ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Payment log',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const PaymentLogScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.request_quote_outlined),
            tooltip: 'Unpaid statement report',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const UnpaidStatementReportScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.redeem_outlined),
            tooltip: 'Loyalty points',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoyaltyPointsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCustomerDialog(context),
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
              child: SegmentedButton<_CustomerFilter>(
                segments: [
                  ButtonSegment(
                    value: _CustomerFilter.withBalance,
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: compactLabel('With balance'),
                    tooltip: 'With balance',
                  ),
                  ButtonSegment(
                    value: _CustomerFilter.all,
                    icon: const Icon(Icons.people_outline),
                    label: compactLabel('All'),
                    tooltip: 'All',
                  ),
                  ButtonSegment(
                    value: _CustomerFilter.archived,
                    icon: const Icon(Icons.archive_outlined),
                    label: compactLabel('Archived'),
                    tooltip: 'Archived',
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (selection) =>
                    setState(() => _filter = selection.first),
              ),
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
                        onSelected: (_) => setState(() => _groupFilter = null),
                      ),
                    ),
                    for (final g in business.customerGroups)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(g),
                          selected: _groupFilter == g,
                          onSelected: (_) => setState(
                            () => _groupFilter = _groupFilter == g ? null : g,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('Ungrouped'),
                        selected: _groupFilter == _ungroupedFilterValue,
                        onSelected: (_) => setState(
                          () => _groupFilter =
                              _groupFilter == _ungroupedFilterValue
                              ? null
                              : _ungroupedFilterValue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (customers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${customers.length} customer(s) · Total: '
                  '₱${customers.fold<double>(0, (sum, c) => sum + customerBalance(c.id, appState.sales, appState.salePayments, appState.cashAdvances, appState.cashAdvancePayments)).toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: customers.isEmpty
                ? _EmptyCustomers(
                    message: switch (_filter) {
                      _CustomerFilter.withBalance => 'Everyone is settled up',
                      _CustomerFilter.archived => 'No archived customers',
                      _CustomerFilter.all => 'No customers yet',
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const Divider(indent: 72),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      final balance = customerBalance(
                        customer.id,
                        appState.sales,
                        appState.salePayments,
                        appState.cashAdvances,
                        appState.cashAdvancePayments,
                      );
                      final unpaidCount = appState.sales
                          .where(
                            (s) =>
                                s.customerId == customer.id &&
                                !s.isDeleted &&
                                !s.paid &&
                                s.saleType == SaleType.customerSale,
                          )
                          .length;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            customer.name.isNotEmpty
                                ? customer.name[0].toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(
                          unpaidCount > 0
                              ? '${customer.name} ($unpaidCount unpaid)'
                              : customer.name,
                        ),
                        subtitle: Text(
                          customer.isPseudoCustomer
                              ? 'Pseudo-customer (excluded from analytics)'
                              : customer.isArchived
                              ? 'Archived - hidden from lists'
                              : [
                                  if (customer.group != null) customer.group!,
                                  if (customer.phone != null) customer.phone!,
                                ].join(' · '),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (balance > 0)
                              Text(
                                '₱${balance.toStringAsFixed(2)}',
                                style: const TextStyle(color: Colors.orange),
                              ),
                            if (!customer.isPseudoCustomer &&
                                !customer.isArchived) ...[
                              const SizedBox(width: 4),
                              if (_copyingSoaLinks.contains(customer.id))
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              else
                                PopupMenuButton<_SoaLinkAction>(
                                  tooltip: 'SOA link actions',
                                  padding: EdgeInsets.zero,
                                  iconSize: 22,
                                  icon: const Icon(Icons.link_outlined),
                                  onSelected: (action) {
                                    switch (action) {
                                      case _SoaLinkAction.copy:
                                        _copySoaLink(customer);
                                      case _SoaLinkAction.share:
                                        _shareSoaLink(customer);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: _SoaLinkAction.copy,
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.copy_outlined),
                                        title: Text('Copy SOA link'),
                                      ),
                                    ),
                                    PopupMenuItem(
                                      value: _SoaLinkAction.share,
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.share_outlined),
                                        title: Text('Share SOA link'),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SwipeableCustomerLedgerScreen(
                              customerIds: customers.map((c) => c.id).toList(),
                              initialIndex: index,
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

  Future<void> _copySoaLink(Customer customer) async {
    if (customer.remoteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer is not synced yet. Try again shortly.'),
        ),
      );
      return;
    }
    setState(() => _copyingSoaLinks.add(customer.id));
    try {
      final link = await _getOrCreateSoaLink(customer);
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${customer.name}\'s SOA link copied.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not copy SOA link: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _copyingSoaLinks.remove(customer.id));
    }
  }

  Future<void> _shareSoaLink(Customer customer) async {
    if (customer.remoteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer is not synced yet. Try again shortly.'),
        ),
      );
      return;
    }
    setState(() => _copyingSoaLinks.add(customer.id));
    try {
      final link = await _getOrCreateSoaLink(customer);
      await SharePlus.instance.share(
        ShareParams(
          subject: 'Your statement of account',
          text: 'Hi ${customer.name}, here is your statement of account: $link',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share SOA link: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _copyingSoaLinks.remove(customer.id));
    }
  }

  Future<String> _getOrCreateSoaLink(Customer customer) async {
    final service = CustomerPortalService(Supabase.instance.client);
    final status = await service.status(customer.remoteId!);
    return status.enabled && status.token != null
        ? service.linkForToken(status.token!)
        : service.rotateLink(customer.remoteId!);
  }

  Future<void> _showAddCustomerDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final availableGroups = context
        .read<BusinessSettingsController>()
        .customerGroups;
    String? group;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New customer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                ),
              ),
              if (availableGroups.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: group,
                  decoration: const InputDecoration(
                    labelText: 'Group (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final g in availableGroups)
                      DropdownMenuItem(value: g, child: Text(g)),
                  ],
                  onChanged: (v) => setDialogState(() => group = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result != true || nameController.text.trim().isEmpty) return;
    if (!context.mounted) return;
    try {
      await context.read<BakeryRepository>().createCustomer(
        Customer(
          id: 0,
          name: nameController.text.trim(),
          group: group,
          phone: phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }
}

class _EmptyCustomers extends StatelessWidget {
  final String message;
  const _EmptyCustomers({required this.message});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.people_outline,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(message, style: Theme.of(context).textTheme.titleMedium),
          if (message == 'No customers yet') ...[
            const SizedBox(height: 6),
            const Text('Tap + to add your first customer.'),
          ],
        ],
      ),
    ),
  );
}
