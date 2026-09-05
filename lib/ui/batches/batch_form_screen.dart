import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/batch.dart';
import '../../models/product.dart';
import '../../repository/bakery_repository.dart';
import '../../utils/app_date_format.dart';
import '../../utils/guarded_action.dart';
import '../widgets/product_avatar.dart';

class BatchFormScreen extends StatefulWidget {
  final int? batchId;
  /// Pre-fills a new batch's fields (product, price, cost, personal flag)
  /// from an existing one - used by "Duplicate batch". Ignored if [batchId]
  /// is set (editing always loads from that batch instead).
  final Batch? duplicateFrom;
  const BatchFormScreen({super.key, this.batchId, this.duplicateFrom});

  @override
  State<BatchFormScreen> createState() => _BatchFormScreenState();
}

class _BatchFormScreenState extends State<BatchFormScreen> {
  final _formKey = GlobalKey<FormState>();
  int? _productId;
  DateTime _batchDate = DateTime.now();
  final _countController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController(text: '0');
  bool _isPersonal = false;
  bool _initialized = false;
  bool _dirty = false;
  bool _suppressDirty = false;

  bool get _isEdit => widget.batchId != null;

  @override
  void initState() {
    super.initState();
    _countController.addListener(_markDirty);
    _priceController.addListener(_markDirty);
    _costController.addListener(_markDirty);
  }

  @override
  void dispose() {
    _countController.dispose();
    _priceController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_suppressDirty || _dirty) return;
    setState(() => _dirty = true);
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits to this batch will be lost.'),
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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    if (_isEdit && !_initialized) {
      final batch = appState.batchById(widget.batchId!);
      if (batch != null) {
        _suppressDirty = true;
        _productId = batch.productId;
        _batchDate = batch.batchDate;
        _countController.text = batch.countProduced.toString();
        _priceController.text = batch.unitPrice.toString();
        _costController.text = batch.unitCost.toString();
        _isPersonal = batch.isPersonal;
        _suppressDirty = false;
      }
      _initialized = true;
    } else if (!_isEdit && !_initialized && widget.duplicateFrom != null) {
      final source = widget.duplicateFrom!;
      _suppressDirty = true;
      _productId = source.productId;
      _batchDate = DateTime.now();
      _countController.text = source.countProduced.toString();
      _priceController.text = source.unitPrice.toString();
      _costController.text = source.unitCost.toString();
      _isPersonal = source.isPersonal;
      _suppressDirty = false;
      _initialized = true;
    }

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard(context) && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Batch' : 'Add Batch')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              initialValue: _productId,
              decoration: const InputDecoration(labelText: 'Product'),
              items: [
                // Archived products stay hidden from new batch creation, but
                // an already-selected one (editing an old batch) still shows.
                for (final p in appState.products
                    .where((p) => !p.isArchived || p.id == _productId))
                  DropdownMenuItem(
                    value: p.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ProductAvatar(imageUrl: p.imageUrl, radius: 12),
                        const SizedBox(width: 8),
                        Text(p.title),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _productId = v;
                _dirty = true;
              }),
              validator: (v) => v == null ? 'Select a product' : null,
            ),
            TextButton.icon(
              onPressed: () => _showAddProductDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('New product'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Batch date'),
              subtitle: Text(
                appDateFormat.format(_batchDate),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _batchDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() {
                    _batchDate = picked;
                    _dirty = true;
                  });
                }
              },
            ),
            TextFormField(
              controller: _countController,
              decoration: const InputDecoration(labelText: 'Count produced'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n <= 0) return 'Enter a positive integer';
                return null;
              },
            ),
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(labelText: 'Unit price'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n < 0) return 'Enter a valid price';
                return null;
              },
            ),
            TextFormField(
              controller: _costController,
              decoration: const InputDecoration(
                labelText: 'Unit cost (optional, for profit tracking)',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return null;
                final n = double.tryParse(v);
                if (n == null || n < 0) return 'Enter a valid cost';
                return null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Personal batch'),
              subtitle: const Text(
                'For your own use - skips remittance entirely.',
              ),
              value: _isPersonal,
              onChanged: (v) => setState(() {
                _isPersonal = v;
                _dirty = true;
              }),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder(
              valueListenable: _countController,
              builder: (context, _, _) => _TotalPreview(
                countController: _countController,
                priceController: _priceController,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _save(context),
              child: Text(_isEdit ? 'Save Changes' : 'Create Batch'),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _showAddProductDialog(BuildContext context) async {
    final controller = TextEditingController();
    var category = ProductCategory.bakery;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Product title'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              SegmentedButton<ProductCategory>(
                segments: const [
                  ButtonSegment(
                      value: ProductCategory.bakery, label: Text('Bakery')),
                  ButtonSegment(
                      value: ProductCategory.merchandise,
                      label: Text('Merchandise')),
                ],
                selected: {category},
                onSelectionChanged: (s) =>
                    setDialogState(() => category = s.first),
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
    final title = controller.text.trim();
    if (result != true || title.isEmpty || !context.mounted) return;
    final repo = context.read<BakeryRepository>();
    await runGuarded(
        context,
        () => repo.createProduct(Product(
              id: 0,
              title: title,
              category: category,
              updatedAt: DateTime.now(),
            )));
  }

  Future<void> _save(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    final repo = context.read<BakeryRepository>();
    final originalUnitPrice =
        _isEdit ? context.read<AppState>().batchById(widget.batchId!)?.unitPrice : null;
    final batch = Batch(
      id: widget.batchId ?? 0,
      productId: _productId!,
      batchDate: _batchDate,
      countProduced: int.parse(_countController.text),
      unitPrice: double.parse(_priceController.text),
      unitCost: double.tryParse(_costController.text) ?? 0,
      totalValue: 0,
      isPersonal: _isPersonal,
      updatedAt: DateTime.now(),
    );
    try {
      if (_isEdit) {
        await repo.updateBatch(batch);
      } else {
        await repo.createBatch(batch);
      }
      _dirty = false;
      if (_isEdit &&
          originalUnitPrice != null &&
          originalUnitPrice != batch.unitPrice &&
          context.mounted) {
        await _offerReprice(context, repo, batch.id, originalUnitPrice, batch.unitPrice);
      }
      if (!context.mounted) return;
      // Heads-up (spec: favorites): a fresh batch of a product someone has
      // favorited is worth flagging right away, not just on the Dashboard.
      if (!_isEdit) {
        final fans = context.read<AppState>().customersFavoriting(_productId!);
        if (fans.isNotEmpty && context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Heads up!'),
              content: Text(
                '${fans.map((c) => c.name).join(', ')} '
                '${fans.length == 1 ? 'has' : 'have'} favorited this product - '
                'let them know it\'s fresh!',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it'),
                ),
              ],
            ),
          );
        }
      }
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _offerReprice(
    BuildContext context,
    BakeryRepository repo,
    int batchId,
    double oldPrice,
    double newPrice,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update existing transactions?'),
        content: Text(
          'The unit price changed from ₱${oldPrice.toStringAsFixed(2)} to '
          '₱${newPrice.toStringAsFixed(2)}. Apply this to every transaction '
          'already recorded in this batch?\n\n'
          'Unpaid transactions just get the new amount. Paid ones also get '
          'the new amount, and the difference from what was actually '
          'collected is recorded as a credit (or debit) on that customer\'s '
          'account - nothing is silently lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Leave them as-is'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Update transactions'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await repo.reconcileBatchUnitPrice(batchId, oldPrice, newPrice);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transactions updated to the new price.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update transactions: $e')));
      }
    }
  }
}

class _TotalPreview extends StatelessWidget {
  final TextEditingController countController;
  final TextEditingController priceController;
  const _TotalPreview({
    required this.countController,
    required this.priceController,
  });

  @override
  Widget build(BuildContext context) {
    final count = int.tryParse(countController.text) ?? 0;
    final price = double.tryParse(priceController.text) ?? 0;
    final total = count * price;
    return Text(
      'Total value: ₱${total.toStringAsFixed(2)}',
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}
