import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../analytics/payment_events.dart';
import '../../app_state.dart';
import '../../utils/app_date_format.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

/// Groups every payment received (see [allPaymentEvents]) by payment
/// method, with a count and subtotal per method - answers "how much came
/// in via GCash vs. Cash" at a glance.
class PaymentsByMethodScreen extends StatefulWidget {
  const PaymentsByMethodScreen({super.key});

  @override
  State<PaymentsByMethodScreen> createState() =>
      _PaymentsByMethodScreenState();
}

class _PaymentsByMethodScreenState extends State<PaymentsByMethodScreen> {
  DateTimeRange? _range;
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final events = allPaymentEvents(appState.sales, appState.salePayments)
        .where((p) =>
            _range == null ||
            (!p.date.isBefore(_range!.start) &&
                !p.date.isAfter(_range!.end)))
        .toList();

    final byMethod = <String, List<PaymentEvent>>{};
    for (final e in events) {
      byMethod.putIfAbsent(e.paymentMethod ?? 'Unspecified', () => []).add(e);
    }
    final methods = byMethod.keys.toList()
      ..sort((a, b) => byMethod[b]!.fold<double>(0, (s, e) => s + e.amount)
          .compareTo(byMethod[a]!.fold<double>(0, (s, e) => s + e.amount)));
    final grandTotal = events.fold<double>(0, (sum, e) => sum + e.amount);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments by Method'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: 'Filter by date range',
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                initialDateRange: _range,
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
          if (_range != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear date filter',
              onPressed: () => setState(() => _range = null),
            ),
        ],
      ),
      body: events.isEmpty
          ? const Center(child: Text('No payments in range.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_range != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${appDateFormat.format(_range!.start)} - '
                      '${appDateFormat.format(_range!.end)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Grand total'),
                        Text(
                          _currency.format(grandTotal),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final method in methods) ...[
                  Card(
                    child: ExpansionTile(
                      initiallyExpanded: _expanded.contains(method),
                      onExpansionChanged: (v) => setState(() {
                        if (v) {
                          _expanded.add(method);
                        } else {
                          _expanded.remove(method);
                        }
                      }),
                      title: Text(method),
                      subtitle: Text('${byMethod[method]!.length} payment(s)'),
                      trailing: Text(
                        _currency.format(byMethod[method]!
                            .fold<double>(0, (s, e) => s + e.amount)),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      children: [
                        for (final e in byMethod[method]!
                          ..sort((a, b) => b.date.compareTo(a.date)))
                          ListTile(
                            dense: true,
                            title: Text(
                                appState.customerById(e.customerId)?.name ??
                                    'Unknown customer'),
                            subtitle: Text(appDateFormat.format(e.date)),
                            trailing: Text(_currency.format(e.amount)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}
