import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../analytics/customer_calculations.dart';
import '../../app_state.dart';
import '../../models/customer.dart';
import '../../models/customer_credit.dart';
import '../../models/loyalty_adjustment.dart';
import '../../models/product.dart';
import '../../models/sale.dart';
import '../../repository/bakery_repository.dart';
import '../../reports/customer_statement_pdf.dart' as statement;
import '../../settings/business_settings_controller.dart';
import '../../theme/theme_controller.dart';
import '../../utils/app_date_format.dart';
import '../../utils/guarded_action.dart';
import '../single_sale/single_sale_screen.dart';
import '../widgets/product_avatar.dart';
import '../widgets/qr_quick_view.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

String _categoryLabel(ProductCategory c) =>
    c == ProductCategory.bakery ? 'Bakery' : 'Merchandise';

String _saleTypeLabel(String value) {
  switch (value) {
    case 'unsold':
      return 'Unsold';
    case 'internal_consumption':
      return 'Internal';
    case 'points_redemption':
      return 'Redeemed';
    default:
      return value;
  }
}

/// Shows a payment date + method picker in one dialog. Returns null if
/// cancelled.
Future<(DateTime date, String? method)?> pickPaymentDateAndMethod(
  BuildContext context, {
  DateTime? initialDate,
  String? helpText,
}) async {
  final methods = context.read<BusinessSettingsController>().paymentMethods;
  var date = initialDate ?? DateTime.now();
  String? method = methods.isEmpty ? null : methods.first;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(helpText ?? 'Payment details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Date: ${appDateFormat.format(date)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setDialogState(() => date = picked);
              },
            ),
            if (methods.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: method,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: [
                  for (final m in methods)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => setDialogState(() => method = v),
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
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return null;
  return (date, method);
}

class CustomerLedgerScreen extends StatelessWidget {
  final int customerId;
  const CustomerLedgerScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final customer = appState.customerById(customerId);
    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer')),
        body: const Center(child: Text('Customer not found.')),
      );
    }
    final sales = appState.sales
        .where((s) => s.customerId == customerId && !s.isDeleted)
        .toList()
      ..sort((a, b) {
        final aUnpaid = !a.paid && a.saleType.value == 'customer_sale';
        final bUnpaid = !b.paid && b.saleType.value == 'customer_sale';
        if (aUnpaid != bUnpaid) return aUnpaid ? -1 : 1;
        return b.saleDate.compareTo(a.saleDate);
      });
    final balance = customerBalance(customerId, appState.sales, appState.salePayments);
    final creditBalance =
        customerCreditBalance(customerId, appState.customerCredits);
    final business = context.watch<BusinessSettingsController>();
    final pointsByCategory = {
      for (final category in ProductCategory.values)
        category: customerPointsBalance(
          customerId,
          appState.sales,
          appState.batches,
          appState.products,
          appState.loyaltyAdjustments,
          category: category,
          pesosPerPoint: business.pesosPerPoint,
          sameDayBonusPercent: business.sameDayBonusPercent,
          redeemPesosPerPoint: business.redeemPesosPerPoint,
          sameDayBonusStartDate: business.sameDayBonusStartDate,
        ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          if (!customer.isPseudoCustomer)
            IconButton(
              icon: const Icon(Icons.redeem_outlined),
              tooltip: 'Redeem points',
              onPressed: () =>
                  _redeemPoints(context, appState, business, pointsByCategory),
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Show payment QR',
            onPressed: () => showQrQuickView(context),
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Share statement (PDF)',
            onPressed: () => _shareStatement(context, appState, customer),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') _editCustomer(context, customer);
              if (value == 'adjust') {
                _adjustPoints(context, customer);
              }
              if (value == 'merge') {
                _mergeCustomer(context, appState, customer);
              }
              if (value == 'markAllPaid') {
                _markAllPaid(context, appState);
              }
            },
            itemBuilder: (context) => [
              if (!customer.isPseudoCustomer)
                const PopupMenuItem(
                  value: 'markAllPaid',
                  child: ListTile(
                    leading: Icon(Icons.checklist),
                    title: Text('Mark all paid'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (!customer.isPseudoCustomer)
                const PopupMenuItem(
                  value: 'adjust',
                  child: ListTile(
                    leading: Icon(Icons.edit_note),
                    title: Text('Adjust points'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('Edit customer'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (!customer.isPseudoCustomer)
                const PopupMenuItem(
                  value: 'merge',
                  child: ListTile(
                    leading: Icon(Icons.merge_type),
                    title: Text('Merge into another customer'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SingleSaleScreen(initialCustomerId: customerId),
          ),
        ),
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Add transaction'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (customer.group != null) Text('Group: ${customer.group}'),
                  if (customer.phone != null) Text('Phone: ${customer.phone}'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Outstanding balance:'),
                      Text(_currency.format(balance),
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  if (creditBalance != 0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Credit available:'),
                        Row(
                          children: [
                            Text(
                              _currency.format(creditBalance),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.green.shade700),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 18),
                              tooltip: 'Apply or refund credit',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.only(left: 4),
                              onPressed: () => _applyOrRefundCredit(
                                  context, customer, creditBalance),
                            ),
                          ],
                        ),
                      ],
                    ),
                  Text('Total orders: ${customerOrderCount(customerId, appState.sales)}'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total spent:'),
                      Text(_currency.format(
                          customerTotalSpent(customerId, appState.sales))),
                    ],
                  ),
                  if (!customer.isPseudoCustomer)
                  for (final category in ProductCategory.values)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text('${_categoryLabel(category)} points:'),
                            IconButton(
                              icon: const Icon(Icons.info_outline, size: 18),
                              tooltip: 'How is this computed?',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(),
                              padding: const EdgeInsets.only(left: 6),
                              onPressed: () => _showPointsBreakdown(
                                  context, appState, business, category),
                            ),
                          ],
                        ),
                        Text(
                          '${pointsByCategory[category]} pts',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.amber.shade800),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (!customer.isPseudoCustomer) ...[
            const SizedBox(height: 16),
            _FavoritesSection(customerId: customerId),
          ],
          const SizedBox(height: 16),
          _TransactionHistorySection(
            customerId: customerId,
            sales: sales,
            onTogglePaid: _togglePaid,
            onRecordPayment: _recordPayment,
          ),
        ],
      ),
    );
  }

  void _showPointsBreakdown(
    BuildContext context,
    AppState appState,
    BusinessSettingsController business,
    ProductCategory category,
  ) {
    // A sale counts toward this category's loyalty pool if its product
    // belongs to this category - mirrors the private filter in
    // customerPointsEarned/Spent. Personal batches still count; "personal"
    // only opts a batch out of remittance and business revenue figures.
    bool inCategory(Sale s) {
      final batch = appState.batchById(s.batchId);
      if (batch == null) return false;
      final product = appState.productById(batch.productId);
      return product != null && product.category == category;
    }

    final earnedRows = appState.sales.where((s) =>
        s.customerId == customerId &&
        !s.isDeleted &&
        s.paid &&
        s.saleType == SaleType.customerSale &&
        s.datePaid != null &&
        inCategory(s)).toList()
      ..sort((a, b) => a.saleDate.compareTo(b.saleDate));

    final spentRows = appState.sales
        .where((s) =>
            s.customerId == customerId &&
            !s.isDeleted &&
            s.saleType == SaleType.pointsRedemption &&
            inCategory(s))
        .toList()
      ..sort((a, b) => a.saleDate.compareTo(b.saleDate));

    // Precompute every row's points before building any widgets - a Builder's
    // callback isn't invoked until the render pass, so accumulating into a
    // shared variable there and reading it from a sibling Text built earlier
    // in this same list would always read the pre-accumulation value (0).
    final earnedEntries = earnedRows.map((s) {
      final sameDayPaid = s.datePaid!.year == s.saleDate.year &&
          s.datePaid!.month == s.saleDate.month &&
          s.datePaid!.day == s.saleDate.day;
      final bonusApplied = sameDayPaid &&
          !s.saleDate.isBefore(business.sameDayBonusStartDate);
      final base = s.amount / business.pesosPerPoint;
      final points =
          bonusApplied ? base * (1 + business.sameDayBonusPercent / 100) : base;
      return (sale: s, sameDay: bonusApplied, points: points);
    }).toList();
    final totalEarned =
        earnedEntries.fold(0.0, (sum, e) => sum + e.points);

    final spentEntries = spentRows.map((s) {
      final batch = appState.batchById(s.batchId);
      final product =
          batch == null ? null : appState.productById(batch.productId);
      final unitPrice = batch?.unitPrice ?? 0;
      final cost = s.quantity * unitPrice / business.redeemPesosPerPoint;
      return (sale: s, product: product, unitPrice: unitPrice, cost: cost);
    }).toList();
    final totalSpent = spentEntries.fold(0.0, (sum, e) => sum + e.cost);

    final adjustmentRows = appState.loyaltyAdjustments
        .where((a) =>
            a.customerId == customerId &&
            !a.isDeleted &&
            a.category == category)
        .toList()
      ..sort((a, b) => a.adjustmentDate.compareTo(b.adjustmentDate));
    final totalAdjustment =
        adjustmentRows.fold(0, (sum, a) => sum + a.points);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_categoryLabel(category)} points computation'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Earn: ₱${business.pesosPerPoint.toStringAsFixed(0)} = 1 point'
                  ' · +${business.sameDayBonusPercent.toStringAsFixed(0)}% bonus if paid same day\n'
                  'Redeem: 1 point = ₱${business.redeemPesosPerPoint.toStringAsFixed(0)} of product value',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Divider(height: 20),
                Text('Earned', style: Theme.of(context).textTheme.titleSmall),
                if (earnedRows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('No paid orders yet.'),
                  ),
                for (final e in earnedEntries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  '${appDateFormat.format(e.sale.saleDate)} · '
                                  '${_currency.format(e.sale.amount)} ÷ ${business.pesosPerPoint.toStringAsFixed(0)}'
                                  '${e.sameDay ? ' × 1.${(business.sameDayBonusPercent / 10).round()}' : ''}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                              if (e.sameDay)
                                Tooltip(
                                  message: 'Paid same day (+${business.sameDayBonusPercent.toStringAsFixed(0)}% bonus)',
                                  child: Icon(Icons.bolt,
                                      size: 14, color: Colors.amber.shade800),
                                ),
                            ],
                          ),
                        ),
                        Text('+${e.points.toStringAsFixed(1)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.green.shade700)),
                      ],
                    ),
                  ),
                if (earnedRows.isNotEmpty) ...[
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total earned (rounded down)'),
                      Text('${totalEarned.floor()} pts'),
                    ],
                  ),
                ],
                const Divider(height: 24),
                Text('Redeemed', style: Theme.of(context).textTheme.titleSmall),
                if (spentRows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('No redemptions yet.'),
                  ),
                for (final e in spentEntries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${appDateFormat.format(e.sale.saleDate)} · '
                            '${e.product?.title ?? '?'} × ${e.sale.quantity} '
                            '(${_currency.format(e.unitPrice)}/unit ÷ ${business.redeemPesosPerPoint.toStringAsFixed(0)})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text('-${e.cost.toStringAsFixed(1)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.red.shade700)),
                      ],
                    ),
                  ),
                if (spentRows.isNotEmpty) ...[
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total redeemed (rounded up)'),
                      Text('${totalSpent.ceil()} pts'),
                    ],
                  ),
                ],
                if (adjustmentRows.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('Adjustments',
                      style: Theme.of(context).textTheme.titleSmall),
                  for (final a in adjustmentRows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${appDateFormat.format(a.adjustmentDate)}'
                              '${a.reason == null || a.reason!.isEmpty ? '' : ' · ${a.reason}'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            '${a.points > 0 ? '+' : ''}${a.points}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: a.points >= 0
                                    ? Colors.green.shade700
                                    : Colors.red.shade700),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total adjustments'),
                      Text('${totalAdjustment > 0 ? '+' : ''}$totalAdjustment pts'),
                    ],
                  ),
                ],
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Balance', style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      '${totalEarned.floor() - totalSpent.ceil() + totalAdjustment} pts',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _redeemPoints(
    BuildContext context,
    AppState appState,
    BusinessSettingsController business,
    Map<ProductCategory, int> pointsByCategory,
  ) async {
    if (pointsByCategory.values.every((p) => p <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No points balance to redeem yet.')),
      );
      return;
    }

    // Personal batches stay redeemable too (personal only opts a batch out
    // of remittance and business revenue figures, not loyalty). Locked
    // (remitted) batches also stay redeemable - same as internal
    // consumption/freebies, zero revenue impact either way, just inventory.
    final availableBatches = sortBatchesUnsoldFirstThenAlpha(
      appState.batches
          .where((b) =>
              !b.isDeleted && remainingQuantity(b, appState.sales) > 0)
          .toList(),
      appState.sales,
      appState.productById,
    );
    if (availableBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No batches with stock to redeem.')),
      );
      return;
    }

    var batchId = availableBatches.first.id;
    var quantity = 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final batch = appState.batchById(batchId);
          final category =
              appState.productById(batch?.productId ?? -1)?.category ??
                  ProductCategory.bakery;
          final pointsBalance = pointsByCategory[category] ?? 0;
          final remaining =
              batch == null ? 0 : remainingQuantity(batch, appState.sales);
          final costPerUnit = batch == null
              ? 0
              : pointsCostForBatch(batch, 1,
                  redeemPesosPerPoint: business.redeemPesosPerPoint);
          final maxByPoints =
              costPerUnit <= 0 ? remaining : pointsBalance ~/ costPerUnit;
          final maxQty = remaining < maxByPoints ? remaining : maxByPoints;
          final totalCost = batch == null
              ? 0
              : pointsCostForBatch(batch, quantity,
                  redeemPesosPerPoint: business.redeemPesosPerPoint);

          return AlertDialog(
            title: const Text('Redeem points'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_categoryLabel(category)} points balance: $pointsBalance'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: batchId,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [
                    for (final b in availableBatches)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text(
                          '${appState.productById(b.productId)?.title ?? '?'} '
                          '(${_currency.format(b.unitPrice)}/unit) · '
                          '${_categoryLabel(appState.productById(b.productId)?.category ?? ProductCategory.bakery)}',
                        ),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() {
                    batchId = v!;
                    quantity = 1;
                  }),
                ),
                const SizedBox(height: 12),
                if (maxQty <= 0)
                  const Text(
                    'Not enough points or stock for this product.',
                    style: TextStyle(color: Colors.red),
                  )
                else
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: quantity > 1
                            ? () => setDialogState(() => quantity--)
                            : null,
                      ),
                      Text('$quantity', style: Theme.of(context).textTheme.titleMedium),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: quantity < maxQty
                            ? () => setDialogState(() => quantity++)
                            : null,
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Text('Cost: $totalCost points',
                    style: Theme.of(context).textTheme.titleMedium),
                Text('Balance after: ${pointsBalance - totalCost}'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    maxQty <= 0 ? null : () => Navigator.of(context).pop(true),
                child: const Text('Redeem'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await runGuarded(
        context,
        () => context.read<BakeryRepository>().addSingleSale(Sale(
              id: 0,
              batchId: batchId,
              customerId: customerId,
              saleDate: DateTime.now(),
              quantity: quantity,
              amount: 0,
              paid: true,
              datePaid: DateTime.now(),
              saleType: SaleType.pointsRedemption,
              updatedAt: DateTime.now(),
            )));
  }

  Future<void> _adjustPoints(BuildContext context, Customer customer) async {
    var category = ProductCategory.bakery;
    final pointsController = TextEditingController();
    final reasonController = TextEditingController();
    var isCredit = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Adjust points'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'For goodwill credits or fixing a mistake - not tied to a '
                'real purchase.',
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: true,
                      icon: Icon(Icons.add),
                      label: Text('Credit')),
                  ButtonSegment(
                      value: false,
                      icon: Icon(Icons.remove),
                      label: Text('Debit')),
                ],
                selected: {isCredit},
                onSelectionChanged: (s) =>
                    setDialogState(() => isCredit = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pointsController,
                decoration: const InputDecoration(labelText: 'Points'),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason (optional)'),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final rawPoints = int.tryParse(pointsController.text);
    if (rawPoints == null || rawPoints <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a positive whole number of points.')),
      );
      return;
    }
    await runGuarded(
        context,
        () => context.read<BakeryRepository>().addLoyaltyAdjustment(
              LoyaltyAdjustment(
                id: 0,
                customerId: customerId,
                category: category,
                points: isCredit ? rawPoints : -rawPoints,
                reason: reasonController.text.trim().isEmpty
                    ? null
                    : reasonController.text.trim(),
                adjustmentDate: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ));
  }

  Future<void> _shareStatement(
    BuildContext context,
    AppState appState,
    Customer customer,
  ) async {
    try {
      final business = context.read<BusinessSettingsController>();
      final seedColor = context.read<ThemeController>().preset.seedColor;
      await business.load();
      await statement.shareCustomerStatement(
        appState,
        customer,
        businessName: business.name,
        enabledQrSlots: business.enabledQrSlots,
        brandColor: PdfColor.fromInt(seedColor.toARGB32()),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not share statement: $e')));
      }
    }
  }

  Future<void> _mergeCustomer(
    BuildContext context,
    AppState appState,
    Customer customer,
  ) async {
    final candidates = appState.customers
        .where((c) =>
            c.id != customer.id && !c.isDeleted && !c.isPseudoCustomer)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    Customer? target;
    final picked = await showDialog<Customer>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Merge "${customer.name}" into...'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'All transactions and points from this customer move to the '
                'one you pick, then this customer is archived.',
              ),
              const SizedBox(height: 12),
              Autocomplete<Customer>(
                displayStringForOption: (c) => c.name,
                optionsBuilder: (value) {
                  if (value.text.isEmpty) return candidates;
                  final query = value.text.toLowerCase();
                  return candidates
                      .where((c) => c.name.toLowerCase().contains(query));
                },
                onSelected: (c) => target = c,
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Target customer',
                      hintText: 'Search customer...',
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(target),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;

    final salesCount = appState.sales
        .where((s) => s.customerId == customer.id && !s.isDeleted)
        .length;
    final adjustmentsCount = appState.loyaltyAdjustments
        .where((a) => a.customerId == customer.id && !a.isDeleted)
        .length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm merge'),
        content: Text(
          'This moves $salesCount transaction(s) and $adjustmentsCount '
          'point adjustment(s) from "${customer.name}" into "${picked.name}", '
          'then archives "${customer.name}". This cannot be undone from the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Merge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await runGuarded(
      context,
      () => context
          .read<BakeryRepository>()
          .mergeCustomers(customer.id, picked.id),
    );
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _editCustomer(BuildContext context, Customer customer) async {
    final nameController = TextEditingController(text: customer.name);
    final phoneController = TextEditingController(text: customer.phone ?? '');
    var isArchived = customer.isArchived;
    var group = customer.group;
    // Include the customer's current group even if it was since removed
    // from Settings, so the dropdown always has a valid matching item.
    final availableGroups = [
      ...context.read<BusinessSettingsController>().customerGroups,
      if (group != null &&
          !context.read<BusinessSettingsController>().customerGroups.contains(group))
        group,
    ];
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit customer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                autofocus: true,
              ),
              TextField(
                controller: phoneController,
                decoration:
                    const InputDecoration(labelText: 'Phone (optional)'),
              ),
              if (availableGroups.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: group,
                  decoration: const InputDecoration(labelText: 'Group (optional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final g in availableGroups)
                      DropdownMenuItem(value: g, child: Text(g)),
                  ],
                  onChanged: (v) => setDialogState(() => group = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hide from customer list'),
                subtitle: const Text(
                  'Archives without deleting - history stays intact',
                ),
                value: isArchived,
                onChanged: (v) => setDialogState(() => isArchived = v),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != true || nameController.text.trim().isEmpty) return;
    if (!context.mounted) return;
    try {
      await context.read<BakeryRepository>().updateCustomer(
        Customer(
          id: customer.id,
          remoteId: customer.remoteId,
          name: nameController.text.trim(),
          phone: phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
          isArchived: isArchived,
          group: group,
          updatedAt: DateTime.now(),
          isDeleted: customer.isDeleted,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _togglePaid(BuildContext context, int saleId, bool paid) async {
    final repo = context.read<BakeryRepository>();
    if (paid) {
      final picked = await pickPaymentDateAndMethod(context);
      if (picked == null || !context.mounted) return;
      await runGuarded(
        context,
        () => repo.markSalePaid(saleId, picked.$1, paymentMethod: picked.$2),
      );
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mark as unpaid?'),
          content: const Text(
            'This clears the payment date and marks the transaction unpaid.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Mark Unpaid'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await runGuarded(context, () => repo.markSaleUnpaid(saleId));
    }
  }

  Future<void> _recordPayment(
    BuildContext context,
    Sale sale,
    double remaining,
  ) async {
    final amountController =
        TextEditingController(text: remaining.toStringAsFixed(2));
    var paymentDate = DateTime.now();
    final methods = context.read<BusinessSettingsController>().paymentMethods;
    String? paymentMethod = methods.isEmpty ? null : methods.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Record payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Remaining balance: ${_currency.format(remaining)}'),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount paid now'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter less than the remaining balance to record a partial '
                'payment - the transaction stays unpaid until it\'s fully '
                'covered.',
                style: TextStyle(fontSize: 12),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date: ${appDateFormat.format(paymentDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: paymentDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setDialogState(() => paymentDate = picked);
                  }
                },
              ),
              if (methods.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: const InputDecoration(labelText: 'Payment method'),
                  items: [
                    for (final m in methods)
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => setDialogState(() => paymentMethod = v),
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
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid payment amount.')),
      );
      return;
    }
    if (amount > remaining + 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Amount can\'t exceed the remaining ${_currency.format(remaining)}.'),
      ));
      return;
    }

    await runGuarded(
      context,
      () => context.read<BakeryRepository>().addSalePayment(SalePayment(
            id: 0,
            saleId: sale.id,
            amount: amount,
            paymentDate: paymentDate,
            paymentMethod: paymentMethod,
            updatedAt: DateTime.now(),
          )),
    );
  }

  Future<void> _markAllPaid(BuildContext context, AppState appState) async {
    final unpaid = appState.sales
        .where((s) =>
            s.customerId == customerId &&
            !s.isDeleted &&
            !s.paid &&
            s.saleType == SaleType.customerSale)
        .toList();
    if (unpaid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No unpaid transactions.')),
      );
      return;
    }
    final totalRemaining = unpaid.fold<double>(
        0, (sum, s) => sum + saleRemainingAmount(s, appState.salePayments));

    final picked = await pickPaymentDateAndMethod(
      context,
      helpText: 'Payment for all ${unpaid.length} transaction(s)',
    );
    if (picked == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark all paid?'),
        content: Text(
          'This marks all ${unpaid.length} unpaid transaction(s) - totaling '
          '${_currency.format(totalRemaining)} still owed - as fully paid on '
          '${appDateFormat.format(picked.$1)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark All Paid'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final repo = context.read<BakeryRepository>();
    await runGuarded(context, () async {
      for (final sale in unpaid) {
        await repo.markSalePaid(sale.id, picked.$1, paymentMethod: picked.$2);
      }
    });
  }

  Future<void> _applyOrRefundCredit(
    BuildContext context,
    Customer customer,
    double creditBalance,
  ) async {
    final amountController =
        TextEditingController(text: creditBalance.abs().toStringAsFixed(2));
    final reasonController = TextEditingController(
      text: creditBalance > 0 ? 'Refunded in cash' : 'Correction',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply or refund credit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current balance: ${_currency.format(creditBalance)}'),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount to deduct from the balance',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (e.g. "Applied to order", "Refunded cash")',
              ),
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
            child: const Text('Record'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final amount = double.tryParse(amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount.')),
      );
      return;
    }

    await runGuarded(
      context,
      () => context.read<BakeryRepository>().addCustomerCredit(CustomerCredit(
            id: 0,
            customerId: customer.id,
            amount: -amount,
            reason: reasonController.text.trim().isEmpty
                ? null
                : reasonController.text.trim(),
            creditDate: DateTime.now(),
            updatedAt: DateTime.now(),
          )),
    );
  }
}

class _TransactionHistorySection extends StatefulWidget {
  final int customerId;
  final List<Sale> sales;
  final void Function(BuildContext, int saleId, bool paid) onTogglePaid;
  final void Function(BuildContext, Sale sale, double remaining) onRecordPayment;

  const _TransactionHistorySection({
    required this.customerId,
    required this.sales,
    required this.onTogglePaid,
    required this.onRecordPayment,
  });

  @override
  State<_TransactionHistorySection> createState() =>
      _TransactionHistorySectionState();
}

class _TransactionHistorySectionState
    extends State<_TransactionHistorySection> {
  bool _selectMode = false;
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final sales = widget.sales;
    final selectableIds = sales
        .where((s) => s.saleType == SaleType.customerSale && !s.paid)
        .map((s) => s.id)
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text('Transaction history (${sales.length})',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            if (selectableIds.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _selectMode = !_selectMode;
                  _selected.clear();
                }),
                icon: Icon(_selectMode ? Icons.close : Icons.checklist),
                label: Text(_selectMode ? 'Cancel' : 'Select'),
              ),
          ],
        ),
        if (sales.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No transactions yet.'),
          ),
        for (final sale in sales)
          Builder(builder: (context) {
            final batch = appState.batchById(sale.batchId);
            final product =
                batch == null ? null : appState.productById(batch.productId);
            final isCustomerSale = sale.saleType == SaleType.customerSale;
            final paidSoFar = isCustomerSale
                ? salePaidAmount(sale.id, appState.salePayments)
                : 0.0;
            final remaining = isCustomerSale
                ? saleRemainingAmount(sale, appState.salePayments)
                : sale.amount;
            final selectable = selectableIds.contains(sale.id);
            return ListTile(
              leading: _selectMode && selectable
                  ? Checkbox(
                      value: _selected.contains(sale.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(sale.id);
                        } else {
                          _selected.remove(sale.id);
                        }
                      }),
                    )
                  : ProductAvatar(imageUrl: product?.imageUrl),
              title: Text(
                '${product?.title ?? ''} × ${sale.quantity}',
              ),
              subtitle: Text(
                (!sale.paid && isCustomerSale && paidSoFar > 0
                        ? '${appDateFormat.format(sale.saleDate)} · '
                            '${_currency.format(paidSoFar)} of ${_currency.format(sale.amount)} paid'
                        : '${appDateFormat.format(sale.saleDate)} · ${_currency.format(sale.amount)}') +
                    (sale.discount > 0
                        ? ' · ${_currency.format(sale.discount)} discount'
                        : ''),
              ),
              trailing: !isCustomerSale
                  ? Chip(
                      label: Text(_saleTypeLabel(sale.saleType.value)),
                      labelStyle: Theme.of(context).textTheme.labelSmall,
                      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )
                  : sale.paid
                      ? Switch(
                          value: true,
                          onChanged: (v) =>
                              widget.onTogglePaid(context, sale.id, v),
                        )
                      : TextButton(
                          onPressed: () =>
                              widget.onRecordPayment(context, sale, remaining),
                          child: Text(_currency.format(remaining)),
                        ),
              onLongPress: (_selectMode || sale.paid)
                  ? null
                  : () => _showSaleActions(context, sale),
            );
          }),
        if (_selectMode && _selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.checklist),
              label: Text('Mark ${_selected.length} selected as paid'),
              onPressed: () => _markSelectedPaid(context),
            ),
          ),
      ],
    );
  }

  Future<void> _markSelectedPaid(BuildContext context) async {
    final picked = await pickPaymentDateAndMethod(
      context,
      helpText: 'Payment for ${_selected.length} selected transaction(s)',
    );
    if (picked == null || !context.mounted) return;
    final repo = context.read<BakeryRepository>();
    final ids = List<int>.from(_selected);
    await runGuarded(context, () async {
      for (final id in ids) {
        await repo.markSalePaid(id, picked.$1, paymentMethod: picked.$2);
      }
    });
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  Future<void> _showSaleActions(BuildContext context, Sale sale) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sale.saleType == SaleType.customerSale)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Move to another customer'),
                onTap: () => Navigator.of(context).pop('move'),
              ),
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Reverse (undo) this transaction'),
              subtitle: const Text('Returns its quantity to the batch'),
              onTap: () => Navigator.of(context).pop('reverse'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'move') {
      await _moveToCustomer(context, sale);
    } else if (action == 'reverse' && context.mounted) {
      await _reverseSale(context, sale);
    }
  }

  Future<void> _moveToCustomer(BuildContext context, Sale sale) async {
    final targetId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _PickCustomerScreen(excludeCustomerId: sale.customerId),
      ),
    );
    if (targetId == null || !context.mounted) return;

    final appState = context.read<AppState>();
    final repo = context.read<BakeryRepository>();
    // If the target customer already has an unpaid entry for this same
    // batch + sale type, fold this one into it instead of leaving two
    // separate unpaid lines for the same product.
    final existingTarget = appState.sales
        .where((s) =>
            s.id != sale.id &&
            s.customerId == targetId &&
            s.batchId == sale.batchId &&
            s.saleType == sale.saleType &&
            !s.paid &&
            !s.isDeleted)
        .toList();

    await runGuarded(context, () async {
      if (existingTarget.length == 1) {
        final merge = existingTarget.first;
        await repo.updateSale(Sale(
          id: merge.id,
          remoteId: merge.remoteId,
          legacyId: merge.legacyId,
          batchId: merge.batchId,
          customerId: merge.customerId,
          saleDate: merge.saleDate,
          quantity: merge.quantity + sale.quantity,
          amount: merge.amount + sale.amount,
          discount: merge.discount + sale.discount,
          paid: false,
          datePaid: null,
          saleType: merge.saleType,
          notes: merge.notes,
          updatedAt: DateTime.now(),
        ));
        // The moved sale's quantity now lives in the merged row above -
        // deleting it frees its own quantity back to "available" in the
        // batch, which nets to zero since the merge just re-added the same
        // amount under the target customer.
        await repo.deleteSale(sale.id);
      } else {
        await repo.updateSale(Sale(
          id: sale.id,
          remoteId: sale.remoteId,
          legacyId: sale.legacyId,
          batchId: sale.batchId,
          customerId: targetId,
          saleDate: sale.saleDate,
          quantity: sale.quantity,
          amount: sale.amount,
          discount: sale.discount,
          paid: sale.paid,
          datePaid: sale.datePaid,
          paymentMethod: sale.paymentMethod,
          saleType: sale.saleType,
          notes: sale.notes,
          updatedAt: DateTime.now(),
        ));
      }
    });
  }

  Future<void> _reverseSale(BuildContext context, Sale sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reverse this transaction?'),
        content: const Text(
          'This fully undoes it - its quantity goes back to the batch\'s '
          'available stock. This cannot be undone from the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reverse'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runGuarded(
        context, () => context.read<BakeryRepository>().deleteSale(sale.id));
  }
}

class _PickCustomerScreen extends StatefulWidget {
  final int excludeCustomerId;
  const _PickCustomerScreen({required this.excludeCustomerId});

  @override
  State<_PickCustomerScreen> createState() => _PickCustomerScreenState();
}

class _PickCustomerScreenState extends State<_PickCustomerScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final customers = appState.customers
        .where((c) =>
            c.id != widget.excludeCustomerId &&
            !c.isArchived &&
            c.name.toLowerCase().contains(_search.toLowerCase()))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Move to customer')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search customer...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: customers.length,
              itemBuilder: (context, index) {
                final c = customers[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?'),
                  ),
                  title: Text(c.name),
                  onTap: () => Navigator.of(context).pop(c.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritesSection extends StatelessWidget {
  final int customerId;
  const _FavoritesSection({required this.customerId});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final favoriteProductIds = appState.customerFavorites
        .where((f) => f.customerId == customerId)
        .map((f) => f.productId)
        .toSet();
    final favoriteProducts = appState.products
        .where((p) => favoriteProductIds.contains(p.id) && !p.isDeleted)
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Favorites', style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: () =>
                      _addFavorite(context, appState, favoriteProductIds),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (favoriteProducts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('No favorites yet.'),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in favoriteProducts)
                      Chip(
                        avatar: ProductAvatar(imageUrl: p.imageUrl, radius: 10),
                        label: Text(p.title),
                        onDeleted: () => runGuarded(
                          context,
                          () => context
                              .read<BakeryRepository>()
                              .removeCustomerFavorite(customerId, p.id),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addFavorite(
    BuildContext context,
    AppState appState,
    Set<int> existingIds,
  ) async {
    final candidates = appState.products
        .where((p) =>
            !p.isDeleted && !p.isArchived && !existingIds.contains(p.id))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No more products to add - every active product is already a favorite.'),
      ));
      return;
    }
    final picked = await showDialog<Product>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Add favorite'),
        children: [
          for (final p in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p),
              child: Row(
                children: [
                  ProductAvatar(imageUrl: p.imageUrl, radius: 14),
                  const SizedBox(width: 8),
                  Text(p.title),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await runGuarded(
      context,
      () => context
          .read<BakeryRepository>()
          .addCustomerFavorite(customerId, picked.id),
    );
  }
}
