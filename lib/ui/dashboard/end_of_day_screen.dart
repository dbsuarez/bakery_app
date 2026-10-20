import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../analytics/customer_calculations.dart';
import '../../analytics/payment_events.dart';
import '../../app_state.dart';
import '../../models/sale.dart';
import '../../utils/money.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

class EndOfDayScreen extends StatefulWidget {
  const EndOfDayScreen({super.key});

  @override
  State<EndOfDayScreen> createState() => _EndOfDayScreenState();
}

class _EndOfDayScreenState extends State<EndOfDayScreen> {
  DateTime _selectedDate = DateUtils.dateOnly(DateTime.now());

  bool _isSelectedDay(DateTime date) =>
      DateUtils.isSameDay(date, _selectedDate);

  bool get _isToday => DateUtils.isSameDay(_selectedDate, DateTime.now());

  void _changeDay(int days) {
    final next = DateUtils.dateOnly(_selectedDate.add(Duration(days: days)));
    if (next.isAfter(DateUtils.dateOnly(DateTime.now()))) return;
    setState(() => _selectedDate = next);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateUtils.dateOnly(DateTime.now()),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = DateUtils.dateOnly(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    final daySales = state.sales
        .where((s) => !s.isDeleted && _isSelectedDay(s.saleDate))
        .toList();
    final customerSales = daySales.where(
      (s) => s.saleType == SaleType.customerSale,
    );
    final payments = allPaymentEvents(
      state.sales,
      state.salePayments,
    ).where((p) => _isSelectedDay(p.date)).toList();
    final expenses = state.expenses.where(
      (e) => !e.isDeleted && _isSelectedDay(e.expenseDate),
    );
    final byMethod = <String, List<num>>{};
    for (final payment in payments) {
      byMethod
          .putIfAbsent(payment.paymentMethod ?? 'Unspecified', () => [])
          .add(payment.amount);
    }
    final newUnpaid = sumMoney(
      customerSales.map((s) => saleRemainingAmount(s, state.salePayments)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Summary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => _changeDay(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(
                    _isToday
                        ? 'Today, ${DateFormat.yMMMMd().format(_selectedDate)}'
                        : DateFormat.yMMMMd().format(_selectedDate),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: _isToday ? null : () => _changeDay(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SummaryTile('Transactions logged', '${daySales.length}'),
          _SummaryTile(
            'Sales value',
            _currency.format(sumMoney(customerSales.map((s) => s.amount))),
          ),
          _SummaryTile(
            'Payments received',
            _currency.format(sumMoney(payments.map((p) => p.amount))),
          ),
          _SummaryTile('New outstanding amount', _currency.format(newUnpaid)),
          _SummaryTile(
            'Expenses',
            _currency.format(sumMoney(expenses.map((e) => e.amount))),
          ),
          const SizedBox(height: 20),
          Text(
            'Payments by method',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (byMethod.isEmpty)
            const ListTile(title: Text('No payments received on this day'))
          else
            for (final entry in byMethod.entries)
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text(entry.key),
                trailing: Text(_currency.format(sumMoney(entry.value))),
              ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryTile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}
