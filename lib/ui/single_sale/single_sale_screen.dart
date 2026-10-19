import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../analytics/customer_calculations.dart';
import '../../app_state.dart';
import '../../celebration/celebration_controller.dart';
import '../../models/customer.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../repository/bakery_repository.dart';
import '../../settings/business_settings_controller.dart';
import '../../utils/app_date_format.dart';
import '../../utils/money.dart';
import '../widgets/product_avatar.dart';
import '../widgets/qr_quick_view.dart';

class SingleSaleScreen extends StatefulWidget {
  final int? initialCustomerId;
  const SingleSaleScreen({super.key, this.initialCustomerId});

  @override
  State<SingleSaleScreen> createState() => _SingleSaleScreenState();
}

class _SingleSaleScreenState extends State<SingleSaleScreen> {
  final _formKey = GlobalKey<FormState>();
  int? _batchId;
  int? _customerId;
  int _quantity = 1;
  final _amountController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  bool _amountEdited = false;
  bool _paid = false;
  DateTime? _datePaid;
  String? _paymentMethod;
  SaleType _saleType = SaleType.customerSale;
  bool _isReservation = false;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _customerId = widget.initialCustomerId;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // Locked (remitted) batches stay selectable here - a zero-revenue
    // internal consumption/freebie entry is allowed even after remittance,
    // it just can't be a real customer sale (enforced by the repository).
    final isRedemption = _saleType == SaleType.pointsRedemption;
    // Personal batches stay redeemable too - personal only opts a batch out
    // of remittance and business revenue figures, not loyalty.
    final selectableBatches = sortBatchesUnsoldFirstThenAlpha(
      appState.batches
          .where(
            (b) =>
                !b.isDeleted &&
                (b.id == _batchId || remainingQuantity(b, appState.sales) > 0),
          )
          .toList(),
      appState.sales,
      appState.productById,
    );
    final batch = _batchId == null ? null : appState.batchById(_batchId!);
    final remaining = batch == null
        ? null
        : remainingQuantity(batch, appState.sales);

    final business = context.watch<BusinessSettingsController>();
    final redemptionCategory = (isRedemption && batch != null)
        ? appState.productById(batch.productId)?.category
        : null;
    final pointsBalance = (_customerId == null || redemptionCategory == null)
        ? 0
        : customerPointsBalance(
            _customerId!,
            appState.sales,
            appState.batches,
            appState.products,
            appState.loyaltyAdjustments,
            category: redemptionCategory,
            pesosPerPoint: business.pesosPerPoint,
            sameDayBonusPercent: business.sameDayBonusPercent,
            redeemPesosPerPoint: business.redeemPesosPerPoint,
            sameDayBonusStartDate: business.sameDayBonusStartDate,
          );
    final costPerUnit = (isRedemption && batch != null)
        ? pointsCostForBatch(
            batch,
            1,
            redeemPesosPerPoint: business.redeemPesosPerPoint,
          )
        : null;
    final maxByPoints = costPerUnit == null
        ? null
        : (costPerUnit <= 0 ? remaining : pointsBalance ~/ costPerUnit);
    final quantityCap = !isRedemption
        ? remaining
        : (remaining == null
              ? maxByPoints
              : (maxByPoints == null
                    ? remaining
                    : (remaining < maxByPoints ? remaining : maxByPoints)));
    final totalCost = (isRedemption && batch != null)
        ? pointsCostForBatch(
            batch,
            _quantity,
            redeemPesosPerPoint: business.redeemPesosPerPoint,
          )
        : 0;

    final discount = double.tryParse(_discountController.text) ?? 0;
    if (!_amountEdited) {
      if (_saleType == SaleType.internalConsumption || isRedemption) {
        _amountController.text = '0';
      } else if (batch != null) {
        final full = _quantity * batch.unitPrice;
        final discounted = full - discount;
        _amountController.text = (discounted < 0 ? 0 : discounted)
            .toStringAsFixed(2);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Single Transaction'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Show payment QR',
            onPressed: () => showQrQuickView(context),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              initialValue: _batchId,
              decoration: const InputDecoration(labelText: 'Batch'),
              items: [
                for (final b in selectableBatches)
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
                            '${appState.productById(b.productId)?.title ?? '?'}'
                            '${b.locked ? ' (Remitted)' : ''}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                _batchId = v;
                _quantity = 1;
              }),
              validator: (v) => v == null ? 'Select a batch' : null,
            ),
            if (batch != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('Remaining: $remaining'),
              ),
            if (isRedemption)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${redemptionCategory == ProductCategory.merchandise ? 'Merchandise' : 'Bakery'} points balance: $pointsBalance'
                  '${batch != null ? ' · Cost: $totalCost pts · Balance after: ${pointsBalance - totalCost}' : ''}',
                  style: TextStyle(color: Colors.amber.shade800),
                ),
              ),
            Autocomplete<Customer>(
              displayStringForOption: (c) => c.name,
              initialValue: TextEditingValue(
                text: _customerId == null
                    ? ''
                    : appState.customerById(_customerId!)?.name ?? '',
              ),
              optionsBuilder: (value) {
                if (value.text.isEmpty) return appState.customers;
                final query = value.text.toLowerCase();
                return appState.customers.where(
                  (c) => c.name.toLowerCase().contains(query),
                );
              },
              onSelected: (c) => setState(() {
                _customerId = c.id;
                _quantity = 1;
              }),
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Customer',
                    hintText: 'Search customer...',
                  ),
                  validator: (_) =>
                      _customerId == null ? 'Select a customer' : null,
                );
              },
            ),
            if (_customerId != null)
              Builder(
                builder: (context) {
                  final creditBalance = customerCreditBalance(
                    _customerId!,
                    appState.customerCredits,
                  );
                  if (creditBalance == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      creditBalance > 0
                          ? 'This customer has ₱${creditBalance.toStringAsFixed(2)} '
                                'credit available - consider deducting it from this order.'
                          : 'This customer has a ₱${creditBalance.abs().toStringAsFixed(2)} '
                                'debit on file.',
                      style: TextStyle(
                        color: creditBalance > 0
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  );
                },
              ),
            DropdownButtonFormField<SaleType>(
              initialValue: _saleType,
              decoration: const InputDecoration(labelText: 'Sale type'),
              items: const [
                DropdownMenuItem(
                  value: SaleType.customerSale,
                  child: Text('Customer sale'),
                ),
                DropdownMenuItem(
                  value: SaleType.internalConsumption,
                  child: Text('Internal consumption (freebie/sample)'),
                ),
                DropdownMenuItem(
                  value: SaleType.pointsRedemption,
                  child: Text('Redeem loyalty points'),
                ),
              ],
              onChanged: (v) => setState(() {
                _saleType = v!;
                _quantity = 1;
                _amountEdited = false;
              }),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Text('Quantity:'),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _setQuantity(_quantity - 1, quantityCap),
                  ),
                  Text(
                    '$_quantity',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: quantityCap != null && _quantity >= quantityCap
                        ? null
                        : () => _setQuantity(_quantity + 1, quantityCap),
                  ),
                  const SizedBox(width: 8),
                  for (final q in [1, 2, 5, 10])
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: OutlinedButton(
                        onPressed: quantityCap != null && q > quantityCap
                            ? null
                            : () => _setQuantity(q, quantityCap),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(36, 32),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text('$q'),
                      ),
                    ),
                ],
              ),
            ),
            if (_saleType == SaleType.customerSale)
              TextFormField(
                controller: _discountController,
                decoration: const InputDecoration(
                  labelText: 'Discount (optional)',
                  helperText:
                      'Knocked off the full price - tracked separately '
                      'from the charged amount',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final n = double.tryParse(v);
                  if (n == null || n < 0) return 'Enter a valid discount';
                  return null;
                },
              ),
            if (_saleType == SaleType.customerSale)
              SwitchListTile(
                title: const Text('Reservation'),
                subtitle: const Text(
                  'Customer has committed to this before the batch is '
                  'actually ready/in stock',
                ),
                value: _isReservation,
                onChanged: (v) => setState(() => _isReservation = v),
              ),
            TextFormField(
              controller: _amountController,
              enabled: !isRedemption,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() => _amountEdited = true),
              validator: (v) {
                final n = double.tryParse(v ?? '');
                if (n == null || n < 0) return 'Enter a valid amount';
                return null;
              },
            ),
            if (!isRedemption)
              SwitchListTile(
                title: const Text('Paid'),
                value: _paid,
                onChanged: (v) => setState(() {
                  _paid = v;
                  _datePaid = v ? (_datePaid ?? DateTime.now()) : null;
                  if (v && _paymentMethod == null) {
                    final methods = business.paymentMethods;
                    _paymentMethod = methods.isEmpty ? null : methods.first;
                  }
                }),
              ),
            if (!isRedemption && _paid)
              ListTile(
                title: Text(
                  'Payment date: ${_datePaid != null ? appDateFormat.format(_datePaid!) : '-'}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _datePaid ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _datePaid = picked);
                },
              ),
            if (!isRedemption && _paid && business.paymentMethods.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: [
                  for (final m in business.paymentMethods)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => setState(() => _paymentMethod = v),
              ),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _save(context),
              child: const Text('Save Transaction'),
            ),
          ],
        ),
      ),
    );
  }

  void _setQuantity(int qty, int? max) {
    if (qty <= 0) return;
    if (max != null && qty > max) qty = max;
    setState(() => _quantity = qty);
  }

  Future<void> _save(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    final repo = context.read<BakeryRepository>();
    final appState = context.read<AppState>();
    final batch = appState.batchById(_batchId!);
    final remainingBefore = batch == null
        ? 0
        : remainingQuantity(batch, appState.sales);
    final quantity = _quantity;
    final isRedemption = _saleType == SaleType.pointsRedemption;
    final countsTowardStock =
        _saleType == SaleType.customerSale ||
        _saleType == SaleType.internalConsumption ||
        isRedemption;
    // Final safety net: state may have drifted since the stepper was last
    // clamped (e.g. another device sold the remaining stock in between).
    if (countsTowardStock && quantity > remainingBefore) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only $remainingBefore left in this batch.')),
      );
      return;
    }
    final business = context.read<BusinessSettingsController>();
    if (isRedemption && batch != null) {
      final category =
          appState.productById(batch.productId)?.category ??
          ProductCategory.bakery;
      final pointsBalance = customerPointsBalance(
        _customerId!,
        appState.sales,
        appState.batches,
        appState.products,
        appState.loyaltyAdjustments,
        category: category,
        pesosPerPoint: business.pesosPerPoint,
        sameDayBonusPercent: business.sameDayBonusPercent,
        redeemPesosPerPoint: business.redeemPesosPerPoint,
        sameDayBonusStartDate: business.sameDayBonusStartDate,
      );
      final cost = pointsCostForBatch(
        batch,
        quantity,
        redeemPesosPerPoint: business.redeemPesosPerPoint,
      );
      if (cost > pointsBalance) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Only $pointsBalance points available - this costs $cost.',
            ),
          ),
        );
        return;
      }
    }
    final paid = isRedemption ? true : _paid;
    final datePaid = isRedemption ? DateTime.now() : (_paid ? _datePaid : null);
    final amount = isRedemption ? 0.0 : double.parse(_amountController.text);
    final discount = _saleType == SaleType.customerSale
        ? (double.tryParse(_discountController.text) ?? 0)
        : 0.0;

    // Unpaid additions fold into this customer's existing unpaid line for
    // the same batch + sale type instead of fragmenting into separate rows.
    // A paid addition always starts a new transaction - it's a distinct
    // payment event, not a continuation of an existing (possibly unpaid)
    // balance.
    Sale? mergeTarget;
    if (!paid) {
      final existing = appState.sales
          .where(
            (s) =>
                s.batchId == _batchId &&
                s.customerId == _customerId &&
                s.saleType == _saleType &&
                !s.paid &&
                !s.isDeleted,
          )
          .toList();
      if (existing.length == 1) mergeTarget = existing.first;
    }

    try {
      if (mergeTarget != null) {
        await repo.updateSale(
          Sale(
            id: mergeTarget.id,
            batchId: mergeTarget.batchId,
            customerId: mergeTarget.customerId,
            saleDate: mergeTarget.saleDate,
            quantity: mergeTarget.quantity + quantity,
            amount: fromCentavos(
              toCentavos(mergeTarget.amount) + toCentavos(amount),
            ),
            discount: fromCentavos(
              toCentavos(mergeTarget.discount) + toCentavos(discount),
            ),
            paid: false,
            datePaid: null,
            saleType: mergeTarget.saleType,
            notes: _notesController.text.isEmpty
                ? mergeTarget.notes
                : _notesController.text,
            isReservation: mergeTarget.isReservation || _isReservation,
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        await repo.addSingleSale(
          Sale(
            id: 0,
            batchId: _batchId!,
            customerId: _customerId!,
            saleDate: DateTime.now(),
            quantity: quantity,
            amount: amount,
            discount: discount,
            paid: paid,
            datePaid: datePaid,
            paymentMethod: paid ? _paymentMethod : null,
            saleType: _saleType,
            notes: _notesController.text.isEmpty ? null : _notesController.text,
            isReservation: _saleType == SaleType.customerSale && _isReservation,
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (!context.mounted) return;
      // Meaningful confetti (spec section 12): the batch just sold out.
      if (countsTowardStock &&
          remainingBefore > 0 &&
          remainingBefore - quantity <= 0) {
        context.read<CelebrationController>().celebrate();
      }
      Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
