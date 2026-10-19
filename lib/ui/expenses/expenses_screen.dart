import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/expense.dart';
import '../../repository/bakery_repository.dart';
import '../../utils/app_date_format.dart';
import '../../utils/guarded_action.dart';
import '../../utils/money.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

const _defaultCategories = [
  'Ingredients',
  'Packaging',
  'Utilities',
  'Rent',
  'Transport',
  'Equipment',
  'Other',
];

/// Standalone business expenses (rent, utilities, packaging, ...) not tied
/// to a batch's own unit cost - feeds into the Dashboard's net profit
/// figure alongside batch cost-of-goods.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final expenses = appState.expenses.where((e) => !e.isDeleted).toList()
      ..sort((a, b) => b.expenseDate.compareTo(a.expenseDate));
    final total = sumMoney(expenses.map((e) => e.amount));

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editExpense(context, null),
        child: const Icon(Icons.add),
      ),
      body: expenses.isEmpty
          ? const Center(child: Text('No expenses recorded yet.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${expenses.length} expense(s) · Total: ${_currency.format(total)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final e in expenses)
                  Card(
                    child: ListTile(
                      title: Text(e.category),
                      subtitle: Text(
                        '${appDateFormat.format(e.expenseDate)}'
                        '${e.notes != null && e.notes!.isNotEmpty ? ' · ${e.notes}' : ''}',
                      ),
                      trailing: Text(
                        _currency.format(e.amount),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      onTap: () => _editExpense(context, e),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _editExpense(BuildContext context, Expense? existing) async {
    final amountController = TextEditingController(
      text: existing == null ? '' : existing.amount.toStringAsFixed(2),
    );
    final notesController = TextEditingController(text: existing?.notes);
    var category = existing?.category ?? _defaultCategories.first;
    var expenseDate = existing?.expenseDate ?? DateTime.now();
    final categories = {
      ..._defaultCategories,
      if (existing != null) existing.category,
    }.toList();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Add expense' : 'Edit expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setDialogState(() => category = v!),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date: ${appDateFormat.format(expenseDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: expenseDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() => expenseDate = picked);
                  }
                },
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !context.mounted) return;
    final repo = context.read<BakeryRepository>();

    if (result == false && existing != null) {
      // "Delete" was tapped (only shown when editing).
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this expense?'),
          content: const Text('This cannot be undone from the app.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        await runGuarded(context, () => repo.deleteExpense(existing.id));
      }
      return;
    }

    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      }
      return;
    }

    await runGuarded(context, () {
      final expense = Expense(
        id: existing?.id ?? 0,
        remoteId: existing?.remoteId,
        amount: amount,
        category: category,
        expenseDate: expenseDate,
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
        updatedAt: DateTime.now(),
      );
      return existing == null
          ? repo.addExpense(expense)
          : repo.updateExpense(expense);
    });
  }
}
