import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../analytics/customer_calculations.dart';
import '../../app_state.dart';
import '../../models/customer.dart';
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
    final balance = customerBalance(customerId, appState.sales);
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
            },
            itemBuilder: (context) => [
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
          Text('Transaction history (${sales.length})',
              style: Theme.of(context).textTheme.titleMedium),
          if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No transactions yet.'),
            ),
          for (final sale in sales)
            ListTile(
              leading: Builder(builder: (context) {
                final batch = appState.batchById(sale.batchId);
                final product =
                    batch == null ? null : appState.productById(batch.productId);
                return ProductAvatar(imageUrl: product?.imageUrl);
              }),
              title: Text(
                '${appState.batchById(sale.batchId) != null ? appState.productById(appState.batchById(sale.batchId)!.productId)?.title ?? '' : ''} '
                '× ${sale.quantity}',
              ),
              subtitle: Text(
                '${appDateFormat.format(sale.saleDate)} · ${_currency.format(sale.amount)}',
              ),
              trailing: sale.saleType.value != 'customer_sale'
                  ? Chip(
                      label: Text(_saleTypeLabel(sale.saleType.value)),
                      labelStyle: Theme.of(context).textTheme.labelSmall,
                      labelPadding:
                          const EdgeInsets.symmetric(horizontal: 6),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    )
                  : Switch(
                      value: sale.paid,
                      onChanged: (v) => _togglePaid(context, sale.id, v),
                    ),
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
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );
      if (picked == null || !context.mounted) return;
      await runGuarded(context, () => repo.markSalePaid(saleId, picked));
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
