import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../app_state.dart';
import '../../celebration/celebration_controller.dart';
import '../../models/batch.dart';
import '../../models/customer.dart';
import '../../models/sale.dart';
import '../../repository/bakery_repository.dart';
import '../../settings/business_settings_controller.dart';
import '../../utils/app_date_format.dart';
import '../widgets/product_avatar.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

class _Row {
  final int customerId;
  final Sale? existingSale;
  int quantity;
  double amount;
  bool amountEdited;
  double discount;
  bool paid;
  DateTime? datePaid;
  String? paymentMethod;
  String? notes;
  SaleType saleType;

  _Row({
    required this.customerId,
    this.existingSale,
    required this.quantity,
    required this.amount,
    this.amountEdited = false,
    this.discount = 0,
    required this.paid,
    this.datePaid,
    this.paymentMethod,
    this.notes,
    this.saleType = SaleType.customerSale,
  });

  factory _Row.fromExisting(Sale sale) {
    return _Row(
      customerId: sale.customerId,
      existingSale: sale,
      quantity: sale.quantity,
      amount: sale.amount,
      amountEdited: true,
      discount: sale.discount,
      paid: sale.paid,
      datePaid: sale.datePaid,
      paymentMethod: sale.paymentMethod,
      notes: sale.notes,
      saleType: sale.saleType,
    );
  }
}

class BatchAddTransactionsScreen extends StatefulWidget {
  final int? initialBatchId;
  const BatchAddTransactionsScreen({super.key, this.initialBatchId});

  @override
  State<BatchAddTransactionsScreen> createState() =>
      _BatchAddTransactionsScreenState();
}

class _BatchAddTransactionsScreenState
    extends State<BatchAddTransactionsScreen> {
  int? _batchId;
  int? _prefilledForBatchId;
  final Map<int, _Row> _rows = {};
  String _search = '';
  bool _defaultPaid = false;
  bool _dirty = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _batchId = widget.initialBatchId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Unsaved customer transactions will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Map<int, List<Sale>> _existingByCustomer(AppState appState) {
    final map = <int, List<Sale>>{};
    for (final s in appState.sales) {
      if (s.batchId != _batchId || s.isDeleted) continue;
      map.putIfAbsent(s.customerId, () => []).add(s);
    }
    return map;
  }

  void _prefillExisting(AppState appState) {
    _rows.clear();
    if (_batchId == null) return;
    for (final entry in _existingByCustomer(appState).entries) {
      if (entry.value.length == 1) {
        _rows[entry.key] = _Row.fromExisting(entry.value.first);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (_batchId != _prefilledForBatchId) {
      _prefilledForBatchId = _batchId;
      _prefillExisting(appState);
    }
    final unlockedBatches = sortBatchesUnsoldFirstThenAlpha(
      appState.batches
          .where((b) =>
              !b.locked &&
              !b.isDeleted &&
              (b.id == _batchId || remainingQuantity(b, appState.sales) > 0))
          .toList(),
      appState.sales,
      appState.productById,
    );
    final batch = _batchId == null ? null : appState.batchById(_batchId!);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('Batch Add Transactions')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              initialValue: _batchId,
              decoration: const InputDecoration(labelText: 'Batch'),
              items: [
                for (final b in unlockedBatches)
                  DropdownMenuItem(
                    value: b.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ProductAvatar(
                          imageUrl: appState.productById(b.productId)?.imageUrl,
                          radius: 12,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${appDateFormat.format(b.batchDate)} - '
                            '${appState.productById(b.productId)?.title ?? '?'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _batchId = v),
            ),
          ),
          if (batch != null) ...[
            _BatchSummary(batch: batch),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: 'Search customers...',
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
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _selectAllVisible(appState),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _prefillExisting(appState);
                      _dirty = false;
                    }),
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Default payment (new entries):'),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Unpaid'),
                    selected: !_defaultPaid,
                    onSelected: (_) => setState(() => _defaultPaid = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Paid'),
                    selected: _defaultPaid,
                    onSelected: (_) => setState(() => _defaultPaid = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _CustomerList(
                batch: batch,
                search: _search,
                rows: _rows,
                existingByCustomer: _existingByCustomer(appState),
                onToggle: (customer) => _toggleCustomer(appState, customer),
                onRowChanged: () => setState(() => _dirty = true),
              ),
            ),
            _SummaryBar(
              batch: batch,
              rows: _rows,
              onSave: () => _save(context, appState, batch),
            ),
          ] else
            const Expanded(
              child: Center(child: Text('Select a batch to begin.')),
            ),
        ],
      ),
      ),
    );
  }

  void _selectAllVisible(AppState appState) {
    final visible = appState.customers.where((c) =>
        !c.isArchived &&
        c.name.toLowerCase().contains(_search.toLowerCase()));
    setState(() {
      for (final c in visible) {
        _rows.putIfAbsent(
          c.id,
          () => _Row(
            customerId: c.id,
            quantity: 1,
            amount: 0,
            paid: _defaultPaid,
            datePaid: _defaultPaid ? DateTime.now() : null,
          ),
        );
      }
      _dirty = true;
    });
  }

  Future<void> _toggleCustomer(AppState appState, Customer customer) async {
    if (_rows.containsKey(customer.id)) {
      // Non-destructive: this only collapses the row back down. If it was
      // an existing transaction, nothing writes to it unless it stays
      // checked at save time, so the underlying row is untouched.
      setState(() {
        _rows.remove(customer.id);
        _dirty = _rows.isNotEmpty;
      });
      return;
    }

    final existingSales = appState.sales
        .where((s) =>
            s.batchId == _batchId &&
            s.customerId == customer.id &&
            !s.isDeleted)
        .toList();

    if (existingSales.length == 1) {
      setState(() {
        _rows[customer.id] = _Row.fromExisting(existingSales.first);
        _dirty = true;
      });
      return;
    }

    if (existingSales.length > 1) {
      final totalQty =
          existingSales.fold<int>(0, (sum, s) => sum + s.quantity);
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${customer.name} already has $totalQty unit(s) '
              'across ${existingSales.length} transactions in this batch'),
          content: const Text('What would you like to do?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('add'),
              child: const Text('Add another transaction'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop('increase'),
              child: const Text('Increase existing'),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'increase') {
        if (!mounted) return;
        await _increaseExisting(appState, customer.id);
        return;
      }
      // 'add' falls through to add a new row below.
    }

    setState(() {
      _rows[customer.id] = _Row(
        customerId: customer.id,
        quantity: 1,
        amount: 0,
        paid: _defaultPaid,
        datePaid: _defaultPaid ? DateTime.now() : null,
      );
      _dirty = true;
    });
  }

  Future<void> _increaseExisting(AppState appState, int customerId) async {
    final existingSales = appState.sales
        .where((s) =>
            s.batchId == _batchId && s.customerId == customerId && !s.isDeleted)
        .toList()
      ..sort((a, b) => b.saleDate.compareTo(a.saleDate));
    if (existingSales.isEmpty) return;
    final sale = existingSales.first;
    final controller = TextEditingController(text: '1');
    final addQty = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Increase quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Add how many units?'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(int.tryParse(controller.text)),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (addQty == null || addQty <= 0 || !mounted) return;
    final batch = appState.batchById(_batchId!);
    final newQty = sale.quantity + addQty;
    final newAmount = sale.amount + (addQty * (batch?.unitPrice ?? 0));
    await context.read<BakeryRepository>().updateSale(
          Sale(
            id: sale.id,
            batchId: sale.batchId,
            customerId: sale.customerId,
            saleDate: sale.saleDate,
            quantity: newQty,
            amount: newAmount,
            paid: sale.paid,
            datePaid: sale.datePaid,
            saleType: sale.saleType,
            notes: sale.notes,
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<void> _save(
    BuildContext context,
    AppState appState,
    Batch batch,
  ) async {
    if (_rows.isEmpty) return;

    var netNewQuantity = 0;
    for (final r in _rows.values) {
      if (r.saleType != SaleType.customerSale) continue;
      final original = r.existingSale;
      netNewQuantity +=
          original == null ? r.quantity : (r.quantity - original.quantity);
    }
    final allocated = allocatedQuantity(batch.id, appState.sales);
    if (allocated + netNewQuantity > batch.countProduced) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Exceeds available units'),
          content: Text(
            'This would allocate ${allocated + netNewQuantity} of '
            '${batch.countProduced} produced. Continue anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }

    final newEntries = <BatchTransactionEntry>[];
    final updatedSales = <Sale>[];
    for (final r in _rows.values) {
      final amount = r.amountEdited ? r.amount : r.quantity * batch.unitPrice;
      final datePaid = r.paid ? (r.datePaid ?? DateTime.now()) : null;
      final original = r.existingSale;
      if (original == null) {
        newEntries.add(BatchTransactionEntry(
          customerId: r.customerId,
          quantity: r.quantity,
          amount: amount,
          discount: r.discount,
          paid: r.paid,
          datePaid: datePaid,
          paymentMethod: r.paid ? r.paymentMethod : null,
          notes: r.notes,
        ));
      } else {
        updatedSales.add(Sale(
          id: original.id,
          batchId: original.batchId,
          customerId: original.customerId,
          saleDate: original.saleDate,
          quantity: r.quantity,
          amount: amount,
          discount: r.discount,
          paid: r.paid,
          datePaid: datePaid,
          paymentMethod: r.paid ? r.paymentMethod : null,
          saleType: r.saleType,
          notes: r.notes,
          updatedAt: DateTime.now(),
        ));
      }
    }

    try {
      final repo = context.read<BakeryRepository>();
      for (final sale in updatedSales) {
        await repo.updateSale(sale);
      }
      if (newEntries.isNotEmpty) {
        await repo.addBatchTransactions(batch.id, newEntries);
      }
      // Meaningful confetti (spec section 12): the batch just sold out.
      if (allocated < batch.countProduced &&
          allocated + netNewQuantity >= batch.countProduced &&
          context.mounted) {
        context.read<CelebrationController>().celebrate();
      }
      _dirty = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved ${newEntries.length} new, ${updatedSales.length} updated.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

class _BatchSummary extends StatelessWidget {
  final Batch batch;
  const _BatchSummary({required this.batch});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final product = appState.productById(batch.productId);
        final allocated = allocatedQuantity(batch.id, appState.sales);
        final remaining = remainingQuantity(batch, appState.sales);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProductAvatar(imageUrl: product?.imageUrl, radius: 14),
                  const SizedBox(width: 8),
                  Text(product?.title ?? '',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Unit price:'),
                  Text(_currency.format(batch.unitPrice)),
                ],
              ),
              Text('Produced: ${batch.countProduced} · '
                  'Allocated: $allocated · Remaining: $remaining'),
            ],
          ),
        );
      },
    );
  }
}

String _existingSummary(List<Sale> sales) {
  final totalQty = sales.fold<int>(0, (sum, s) => sum + s.quantity);
  if (sales.length == 1) {
    return 'Already in batch · ${sales.first.paid ? 'Paid' : 'Unpaid'}';
  }
  final paidCount = sales.where((s) => s.paid).length;
  return 'Already in batch: $totalQty units · '
      '$paidCount paid, ${sales.length - paidCount} unpaid';
}

class _CustomerList extends StatelessWidget {
  final Batch batch;
  final String search;
  final Map<int, _Row> rows;
  final Map<int, List<Sale>> existingByCustomer;
  final void Function(Customer) onToggle;
  final VoidCallback onRowChanged;

  const _CustomerList({
    required this.batch,
    required this.search,
    required this.rows,
    required this.existingByCustomer,
    required this.onToggle,
    required this.onRowChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final customers = appState.customers
            .where((c) =>
                !c.isArchived &&
                c.name.toLowerCase().contains(search.toLowerCase()))
            .toList()
          ..sort((a, b) {
            final aUnpaid =
                (existingByCustomer[a.id] ?? const []).any((s) => !s.paid);
            final bUnpaid =
                (existingByCustomer[b.id] ?? const []).any((s) => !s.paid);
            if (aUnpaid != bUnpaid) return aUnpaid ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

        return ListView.builder(
          itemCount: customers.length,
          itemBuilder: (context, index) {
            final customer = customers[index];
            final row = rows[customer.id];
            final existingSales = existingByCustomer[customer.id];
            final alreadyInBatch =
                existingSales != null && existingSales.isNotEmpty;
            return Container(
              color: alreadyInBatch
                  ? Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.3)
                  : null,
              child: Column(
                children: [
                  CheckboxListTile(
                    value: row != null,
                    onChanged: (_) => onToggle(customer),
                    title: Text(customer.name),
                    subtitle: alreadyInBatch
                        ? Text(_existingSummary(existingSales))
                        : null,
                  ),
                  if (row != null)
                    _RowEditor(
                      batch: batch,
                      row: row,
                      onChanged: onRowChanged,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _RowEditor extends StatefulWidget {
  final Batch batch;
  final _Row row;
  final VoidCallback onChanged;
  const _RowEditor(
      {required this.batch, required this.row, required this.onChanged});

  @override
  State<_RowEditor> createState() => _RowEditorState();
}

class _RowEditorState extends State<_RowEditor> {
  late final TextEditingController _amountController;
  late final TextEditingController _discountController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.row.amountEdited
          ? widget.row.amount.toStringAsFixed(2)
          : (widget.row.quantity * widget.batch.unitPrice).toStringAsFixed(2),
    );
    _discountController =
        TextEditingController(text: widget.row.discount.toStringAsFixed(2));
    _notesController = TextEditingController(text: widget.row.notes);
  }

  void _setQuantity(int qty) {
    if (qty <= 0) return;
    setState(() {
      widget.row.quantity = qty;
      if (!widget.row.amountEdited) {
        widget.row.amount = qty * widget.batch.unitPrice;
        _amountController.text = widget.row.amount.toStringAsFixed(2);
      }
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.existingSale != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Editing existing transaction',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _setQuantity(row.quantity - 1),
              ),
              Text('${row.quantity}',
                  style: Theme.of(context).textTheme.titleMedium),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _setQuantity(row.quantity + 1),
              ),
              const SizedBox(width: 8),
              for (final q in [1, 2, 5, 10])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: OutlinedButton(
                    onPressed: () => _setQuantity(q),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(36, 32),
                      padding: EdgeInsets.zero,
                    ),
                    child: Text('$q'),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(labelText: 'Final amount'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    final n = double.tryParse(v);
                    if (n != null) {
                      row.amount = n;
                      row.amountEdited = true;
                      widget.onChanged();
                    }
                  },
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discountController,
                  decoration:
                      const InputDecoration(labelText: 'Discount (optional)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    row.discount = double.tryParse(v) ?? 0;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              const Text('Paid'),
              Switch(
                value: row.paid,
                onChanged: (v) {
                  setState(() {
                    row.paid = v;
                    row.datePaid = v ? (row.datePaid ?? DateTime.now()) : null;
                  });
                  widget.onChanged();
                },
              ),
            ],
          ),
          if (row.paid)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                'Payment date: ${row.datePaid != null ? appDateFormat.format(row.datePaid!) : '-'}',
              ),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: row.datePaid ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => row.datePaid = picked);
                  widget.onChanged();
                }
              },
            ),
          if (row.paid)
            Builder(builder: (context) {
              final methods =
                  context.watch<BusinessSettingsController>().paymentMethods;
              if (methods.isEmpty) return const SizedBox.shrink();
              row.paymentMethod ??= methods.first;
              return DropdownButtonFormField<String>(
                initialValue: row.paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: [
                  for (final m in methods)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) {
                  setState(() => row.paymentMethod = v);
                  widget.onChanged();
                },
              );
            }),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
            onChanged: (v) {
              row.notes = v.isEmpty ? null : v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final Batch batch;
  final Map<int, _Row> rows;
  final VoidCallback onSave;

  const _SummaryBar(
      {required this.batch, required this.rows, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final newRows = rows.values.where((r) => r.existingSale == null).toList();
    final updatedRows =
        rows.values.where((r) => r.existingSale != null).toList();
    final totalQty = rows.values.fold<int>(0, (s, r) => s + r.quantity);
    final totalAmount = rows.values.fold<double>(
        0,
        (s, r) =>
            s + (r.amountEdited ? r.amount : r.quantity * batch.unitPrice));
    return Consumer<AppState>(
      builder: (context, appState, _) {
        var netNewQuantity = 0;
        for (final r in rows.values) {
          final original = r.existingSale;
          netNewQuantity +=
              original == null ? r.quantity : (r.quantity - original.quantity);
        }
        final allocated = allocatedQuantity(batch.id, appState.sales);
        final remainingAfter = batch.countProduced - allocated - netNewQuantity;
        return Material(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${rows.length} customers · $totalQty units · '
                  '${_currency.format(totalAmount)}',
                ),
                Text('Remaining after save: $remainingAfter'),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: rows.isEmpty ? null : onSave,
                  child: Text(
                    'Save (${newRows.length} new, ${updatedRows.length} updated)',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
