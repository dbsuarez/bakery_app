import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/batch.dart' as m;
import '../models/customer.dart' as m;
import '../models/customer_credit.dart' as m;
import '../models/customer_favorite.dart' as m;
import '../models/loyalty_adjustment.dart' as m;
import '../models/product.dart' as m;
import '../models/sale.dart' as m;
import 'bakery_repository.dart';

/// Supabase primary keys are UUIDs, but the shared [BakeryRepository]
/// interface (and the domain models) use `int` ids to match the local
/// Drift-backed repository's autoincrement keys. This mapper assigns a
/// stable, session-local int to each UUID the first time it's seen, so the
/// UI can treat ids as opaque ints regardless of which repository is active.
class _IdMapper {
  final Map<String, int> _uuidToInt = {};
  final Map<int, String> _intToUuid = {};
  int _next = 1;

  int toInt(String uuid) {
    return _uuidToInt.putIfAbsent(uuid, () {
      final id = _next++;
      _intToUuid[id] = uuid;
      return id;
    });
  }

  String toUuid(int id) {
    final uuid = _intToUuid[id];
    if (uuid == null) {
      throw StateError('No known Supabase row for local id $id');
    }
    return uuid;
  }
}

String _dateOnly(DateTime dt) => dt.toIso8601String().split('T').first;

class RemoteRepository implements BakeryRepository {
  final SupabaseClient client;

  /// Set whenever a background poll fails - surfaced in Settings so a
  /// silent connectivity problem (data just stops updating) is visible
  /// instead of the app quietly showing stale/empty data forever.
  final ValueNotifier<String?> lastFetchError = ValueNotifier(null);

  /// Diagnostic: what the last successful poll of each table actually
  /// returned (row count + when), so an unexpected "0 rows" (RLS/auth
  /// mismatch) is distinguishable from "poll never ran at all".
  final ValueNotifier<Map<String, String>> lastFetchInfo = ValueNotifier({});

  final _productIds = _IdMapper();
  final _customerIds = _IdMapper();
  final _batchIds = _IdMapper();
  final _saleIds = _IdMapper();
  final _loyaltyAdjustmentIds = _IdMapper();
  final _salePaymentIds = _IdMapper();
  final _customerCreditIds = _IdMapper();

  RemoteRepository(this.client);

  m.Product _productFromRow(Map<String, dynamic> row) => m.Product(
        id: _productIds.toInt(row['id'] as String),
        remoteId: row['id'] as String,
        title: row['title'] as String,
        imageUrl: row['image_url'] as String?,
        category: m.ProductCategory.fromValue(
            row['category'] as String? ?? 'bakery'),
        isArchived: row['is_archived'] as bool? ?? false,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDirty: false,
        isDeleted: row['is_deleted'] as bool,
      );

  m.Customer _customerFromRow(Map<String, dynamic> row) => m.Customer(
        id: _customerIds.toInt(row['id'] as String),
        remoteId: row['id'] as String,
        name: row['name'] as String,
        phone: row['phone'] as String?,
        isArchived: row['is_archived'] as bool,
        group: row['group_name'] as String?,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDirty: false,
        isDeleted: row['is_deleted'] as bool,
      );

  m.Batch _batchFromRow(Map<String, dynamic> row) => m.Batch(
        id: _batchIds.toInt(row['id'] as String),
        remoteId: row['id'] as String,
        productId: _productIds.toInt(row['product_id'] as String),
        batchDate: DateTime.parse(row['batch_date'] as String),
        countProduced: row['count_produced'] as int,
        unitPrice: (row['unit_price'] as num).toDouble(),
        unitCost: (row['unit_cost'] as num).toDouble(),
        totalValue: (row['total_value'] as num).toDouble(),
        remitted: row['remitted'] as bool,
        dateRemitted: row['date_remitted'] == null
            ? null
            : DateTime.parse(row['date_remitted'] as String),
        locked: row['locked'] as bool,
        isPersonal: row['is_personal'] as bool? ?? false,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDirty: false,
        isDeleted: row['is_deleted'] as bool,
      );

  m.Sale _saleFromRow(Map<String, dynamic> row) => m.Sale(
        id: _saleIds.toInt(row['id'] as String),
        remoteId: row['id'] as String,
        batchId: _batchIds.toInt(row['batch_id'] as String),
        customerId: _customerIds.toInt(row['customer_id'] as String),
        saleDate: DateTime.parse(row['sale_date'] as String),
        quantity: row['quantity'] as int,
        amount: (row['amount'] as num).toDouble(),
        discount: (row['discount'] as num?)?.toDouble() ?? 0,
        paid: row['paid'] as bool,
        datePaid: row['date_paid'] == null
            ? null
            : DateTime.parse(row['date_paid'] as String),
        paymentMethod: row['payment_method'] as String?,
        saleType: m.SaleType.fromValue(row['sale_type'] as String),
        notes: row['notes'] as String?,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDirty: false,
        isDeleted: row['is_deleted'] as bool,
      );

  m.LoyaltyAdjustment _loyaltyAdjustmentFromRow(Map<String, dynamic> row) =>
      m.LoyaltyAdjustment(
        id: _loyaltyAdjustmentIds.toInt(row['id'] as String),
        remoteId: row['id'] as String,
        customerId: _customerIds.toInt(row['customer_id'] as String),
        category: m.ProductCategory.fromValue(row['category'] as String),
        points: row['points'] as int,
        reason: row['reason'] as String?,
        adjustmentDate: DateTime.parse(row['adjustment_date'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDirty: false,
        isDeleted: row['is_deleted'] as bool,
      );

  m.SalePayment _salePaymentFromRow(Map<String, dynamic> row) =>
      m.SalePayment(
        id: _salePaymentIds.toInt(row['id'] as String),
        remoteId: row['id'] as String,
        saleId: _saleIds.toInt(row['sale_id'] as String),
        amount: (row['amount'] as num).toDouble(),
        paymentDate: DateTime.parse(row['payment_date'] as String),
        paymentMethod: row['payment_method'] as String?,
        notes: row['notes'] as String?,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDirty: false,
        isDeleted: row['is_deleted'] as bool,
      );

  m.CustomerCredit _customerCreditFromRow(Map<String, dynamic> row) =>
      m.CustomerCredit(
        id: _customerCreditIds.toInt(row['id'] as String),
        remoteId: row['id'] as String,
        customerId: _customerIds.toInt(row['customer_id'] as String),
        amount: (row['amount'] as num).toDouble(),
        reason: row['reason'] as String?,
        saleId: row['sale_id'] == null
            ? null
            : _saleIds.toInt(row['sale_id'] as String),
        creditDate: DateTime.parse(row['credit_date'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDirty: false,
        isDeleted: row['is_deleted'] as bool,
      );

  m.CustomerFavorite _customerFavoriteFromRow(Map<String, dynamic> row) =>
      m.CustomerFavorite(
        customerId: _customerIds.toInt(row['customer_id'] as String),
        productId: _productIds.toInt(row['product_id'] as String),
      );

  // Realtime's `.stream()` depends on a long-lived WebSocket connection,
  // which is far more sensitive to flaky mobile networks/DNS than a plain
  // REST request (a dropped WS never recovers on its own and silently
  // yields zero rows forever). Poll with plain `.select()` calls instead -
  // slightly less "live" but it only ever needs the request type that's
  // actually proven reliable.
  Stream<List<Map<String, dynamic>>> _watchTable(
    String table,
    String orderColumn, {
    required bool ascending,
    bool filterDeleted = true,
  }) async* {
    while (true) {
      try {
        final query = client.from(table).select();
        final rows = await (filterDeleted
                ? query.eq('is_deleted', false)
                : query)
            .order(orderColumn, ascending: ascending)
            .timeout(const Duration(seconds: 15));
        lastFetchError.value = null;
        final now = DateTime.now();
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        final ss = now.second.toString().padLeft(2, '0');
        lastFetchInfo.value = {
          ...lastFetchInfo.value,
          table: '${rows.length} rows @ $hh:$mm:$ss',
        };
        yield rows;
      } catch (e) {
        // Keep the stream alive on a transient failure; the UI just keeps
        // showing the last successfully-fetched values.
        lastFetchError.value = '$table: $e';
      }
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  @override
  Stream<List<m.Product>> watchProducts() {
    return _watchTable('products', 'title', ascending: true)
        .map((rows) => rows.map(_productFromRow).toList());
  }

  @override
  Stream<List<m.Customer>> watchCustomers() {
    return _watchTable('customers', 'name', ascending: true)
        .map((rows) => rows.map(_customerFromRow).toList());
  }

  @override
  Stream<List<m.Batch>> watchBatches() {
    return _watchTable('batches', 'batch_date', ascending: false)
        .map((rows) => rows.map(_batchFromRow).toList());
  }

  @override
  Stream<List<m.Sale>> watchSales() {
    return _watchTable('sales', 'sale_date', ascending: false)
        .map((rows) => rows.map(_saleFromRow).toList());
  }

  @override
  Stream<List<m.LoyaltyAdjustment>> watchLoyaltyAdjustments() {
    return _watchTable('loyalty_adjustments', 'adjustment_date',
            ascending: false)
        .map((rows) => rows.map(_loyaltyAdjustmentFromRow).toList());
  }

  @override
  Stream<List<m.SalePayment>> watchSalePayments() {
    return _watchTable('sale_payments', 'payment_date', ascending: false)
        .map((rows) => rows.map(_salePaymentFromRow).toList());
  }

  @override
  Stream<List<m.CustomerCredit>> watchCustomerCredits() {
    return _watchTable('customer_credits', 'credit_date', ascending: false)
        .map((rows) => rows.map(_customerCreditFromRow).toList());
  }

  @override
  Stream<List<m.CustomerFavorite>> watchCustomerFavorites() {
    return _watchTable('customer_favorites', 'created_at',
            ascending: false, filterDeleted: false)
        .map((rows) => rows.map(_customerFavoriteFromRow).toList());
  }

  @override
  Future<void> createProduct(m.Product product) async {
    await client.from('products').insert({
      'title': product.title,
      'image_url': product.imageUrl,
      'category': product.category.value,
    });
  }

  @override
  Future<void> updateProduct(m.Product product) async {
    await client.from('products').update({
      'title': product.title,
      'image_url': product.imageUrl,
      'category': product.category.value,
      'is_archived': product.isArchived,
    }).eq('id', _productIds.toUuid(product.id));
  }

  @override
  Future<void> createCustomer(m.Customer customer) async {
    await client.from('customers').insert({
      'name': customer.name,
      'phone': customer.phone,
      'group_name': customer.group,
    });
  }

  @override
  Future<void> updateCustomer(m.Customer customer) async {
    await client.from('customers').update({
      'name': customer.name,
      'phone': customer.phone,
      'is_archived': customer.isArchived,
      'group_name': customer.group,
    }).eq('id', _customerIds.toUuid(customer.id));
  }

  @override
  Future<void> createBatch(m.Batch batch) async {
    await client.from('batches').insert({
      'product_id': _productIds.toUuid(batch.productId),
      'batch_date': _dateOnly(batch.batchDate),
      'count_produced': batch.countProduced,
      'unit_price': batch.unitPrice,
      'unit_cost': batch.unitCost,
      'total_value': batch.countProduced * batch.unitPrice,
      'is_personal': batch.isPersonal,
    });
  }

  @override
  Future<void> updateBatch(m.Batch batch) async {
    final uuid = _batchIds.toUuid(batch.id);
    final existing =
        await client.from('batches').select('locked').eq('id', uuid).single();
    if (existing['locked'] as bool) {
      throw StateError('Cannot edit a locked (remitted) batch.');
    }
    await client.from('batches').update({
      'product_id': _productIds.toUuid(batch.productId),
      'batch_date': _dateOnly(batch.batchDate),
      'count_produced': batch.countProduced,
      'unit_price': batch.unitPrice,
      'unit_cost': batch.unitCost,
      'total_value': batch.countProduced * batch.unitPrice,
      'is_personal': batch.isPersonal,
    }).eq('id', uuid);
  }

  @override
  Future<void> addSingleSale(m.Sale sale) async {
    if (sale.quantity <= 0) {
      throw ArgumentError('Quantity must be a positive integer.');
    }
    // A locked (remitted) batch's revenue is already settled, so a real
    // customer sale can't be backdated onto it. Zero-revenue internal
    // consumption/freebie entries are exempt - they only adjust inventory
    // accounting, not money already remitted.
    if (sale.saleType == m.SaleType.customerSale) {
      final batchUuid = _batchIds.toUuid(sale.batchId);
      final existing = await client
          .from('batches')
          .select('locked')
          .eq('id', batchUuid)
          .single();
      if (existing['locked'] as bool) {
        throw StateError(
          'Cannot add a customer sale to a locked (remitted) batch.',
        );
      }
    }
    await client.from('sales').insert({
      'batch_id': _batchIds.toUuid(sale.batchId),
      'customer_id': _customerIds.toUuid(sale.customerId),
      'sale_date': _dateOnly(sale.saleDate),
      'quantity': sale.quantity,
      'amount': sale.amount,
      'discount': sale.discount,
      'paid': sale.paid,
      'date_paid': sale.datePaid == null ? null : _dateOnly(sale.datePaid!),
      'payment_method': sale.paymentMethod,
      'sale_type': sale.saleType.value,
      'notes': sale.notes,
    });
  }

  @override
  Future<void> updateSale(m.Sale sale) async {
    if (sale.quantity <= 0) {
      throw ArgumentError('Quantity must be a positive integer.');
    }
    await client.from('sales').update({
      'batch_id': _batchIds.toUuid(sale.batchId),
      'customer_id': _customerIds.toUuid(sale.customerId),
      'sale_date': _dateOnly(sale.saleDate),
      'quantity': sale.quantity,
      'amount': sale.amount,
      'discount': sale.discount,
      'paid': sale.paid,
      'date_paid': sale.datePaid == null ? null : _dateOnly(sale.datePaid!),
      'payment_method': sale.paymentMethod,
      'sale_type': sale.saleType.value,
      'notes': sale.notes,
    }).eq('id', _saleIds.toUuid(sale.id));
  }

  @override
  Future<void> addBatchTransactions(
    int batchId,
    List<m.BatchTransactionEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    for (final entry in entries) {
      if (entry.quantity <= 0) {
        throw ArgumentError('Quantity must be a positive integer.');
      }
    }
    final uuid = _batchIds.toUuid(batchId);
    final existing =
        await client.from('batches').select('locked').eq('id', uuid).single();
    if (existing['locked'] as bool) {
      throw StateError('Cannot add transactions to a locked batch.');
    }
    final now = _dateOnly(DateTime.now());
    await client.from('sales').insert([
      for (final entry in entries)
        {
          'batch_id': uuid,
          'customer_id': _customerIds.toUuid(entry.customerId),
          'sale_date': now,
          'quantity': entry.quantity,
          'amount': entry.amount,
          'discount': entry.discount,
          'paid': entry.paid,
          'date_paid':
              entry.datePaid == null ? null : _dateOnly(entry.datePaid!),
          'payment_method': entry.paymentMethod,
          'notes': entry.notes,
        },
    ]);
  }

  @override
  Future<void> addSalePayment(m.SalePayment payment) async {
    if (payment.amount <= 0) {
      throw ArgumentError('Payment amount must be positive.');
    }
    final saleUuid = _saleIds.toUuid(payment.saleId);
    await client.from('sale_payments').insert({
      'sale_id': saleUuid,
      'amount': payment.amount,
      'payment_date': _dateOnly(payment.paymentDate),
      'payment_method': payment.paymentMethod,
      'notes': payment.notes,
    });

    final sale = await client
        .from('sales')
        .select('amount')
        .eq('id', saleUuid)
        .single();
    final saleAmount = (sale['amount'] as num).toDouble();
    final existingPayments = await client
        .from('sale_payments')
        .select('amount')
        .eq('sale_id', saleUuid)
        .eq('is_deleted', false);
    final totalPaid = existingPayments.fold<double>(
        0, (sum, row) => sum + (row['amount'] as num).toDouble());
    // Small epsilon so floating-point rounding never leaves a fully-paid
    // sale stuck open by a fraction of a centavo.
    if (totalPaid >= saleAmount - 0.01) {
      await client.from('sales').update({
        'paid': true,
        'date_paid': _dateOnly(payment.paymentDate),
        'payment_method': payment.paymentMethod,
      }).eq('id', saleUuid);
    }
  }

  @override
  Future<void> markSalePaid(
    int saleId,
    DateTime paymentDate, {
    String? paymentMethod,
  }) async {
    await client.from('sales').update({
      'paid': true,
      'date_paid': _dateOnly(paymentDate),
      'payment_method': paymentMethod,
    }).eq('id', _saleIds.toUuid(saleId));
  }

  @override
  Future<void> markSaleUnpaid(int saleId) async {
    await client.from('sales').update({
      'paid': false,
      'date_paid': null,
    }).eq('id', _saleIds.toUuid(saleId));
  }

  @override
  Future<void> markBatchRemitted(int batchId, DateTime dateRemitted) async {
    await client.from('batches').update({
      'remitted': true,
      'date_remitted': _dateOnly(dateRemitted),
      'locked': true,
    }).eq('id', _batchIds.toUuid(batchId));
  }

  @override
  Future<void> unlockBatch(int batchId) async {
    await client
        .from('batches')
        .update({'locked': false}).eq('id', _batchIds.toUuid(batchId));
  }

  @override
  Future<void> lockBatch(int batchId) async {
    await client
        .from('batches')
        .update({'locked': true}).eq('id', _batchIds.toUuid(batchId));
  }

  @override
  Future<void> revertBatchRemittance(int batchId) async {
    await client.from('batches').update({
      'remitted': false,
      'date_remitted': null,
      'locked': false,
    }).eq('id', _batchIds.toUuid(batchId));
  }

  @override
  Future<void> deleteSale(int saleId) async {
    await client
        .from('sales')
        .update({'is_deleted': true}).eq('id', _saleIds.toUuid(saleId));
  }

  @override
  Future<void> addLoyaltyAdjustment(m.LoyaltyAdjustment adjustment) async {
    await client.from('loyalty_adjustments').insert({
      'customer_id': _customerIds.toUuid(adjustment.customerId),
      'category': adjustment.category.value,
      'points': adjustment.points,
      'reason': adjustment.reason,
      'adjustment_date': _dateOnly(adjustment.adjustmentDate),
    });
  }

  @override
  Future<void> addCustomerCredit(m.CustomerCredit credit) async {
    await client.from('customer_credits').insert({
      'customer_id': _customerIds.toUuid(credit.customerId),
      'amount': credit.amount,
      'reason': credit.reason,
      'sale_id': credit.saleId == null ? null : _saleIds.toUuid(credit.saleId!),
      'credit_date': _dateOnly(credit.creditDate),
    });
  }

  @override
  Future<void> reconcileBatchUnitPrice(
    int batchId,
    double oldUnitPrice,
    double newUnitPrice,
  ) async {
    final batchUuid = _batchIds.toUuid(batchId);
    final rows = await client
        .from('sales')
        .select()
        .eq('batch_id', batchUuid)
        .eq('is_deleted', false)
        .eq('sale_type', m.SaleType.customerSale.value);
    for (final row in rows) {
      final saleUuid = row['id'] as String;
      final quantity = row['quantity'] as int;
      final discount = (row['discount'] as num?)?.toDouble() ?? 0;
      final oldAmount = (row['amount'] as num).toDouble();
      final paid = row['paid'] as bool;
      final rawNewAmount = quantity * newUnitPrice - discount;
      final newAmount = rawNewAmount < 0 ? 0.0 : rawNewAmount;

      if (paid) {
        final diff = oldAmount - newAmount;
        if (diff.abs() > 0.005) {
          await client.from('customer_credits').insert({
            'customer_id': row['customer_id'],
            'amount': diff,
            'reason': 'Batch unit price corrected from '
                '₱${oldUnitPrice.toStringAsFixed(2)} to '
                '₱${newUnitPrice.toStringAsFixed(2)}',
            'sale_id': saleUuid,
          });
        }
      }
      await client
          .from('sales')
          .update({'amount': newAmount}).eq('id', saleUuid);
    }
  }

  @override
  Future<void> mergeCustomers(int fromCustomerId, int intoCustomerId) async {
    final fromUuid = _customerIds.toUuid(fromCustomerId);
    final intoUuid = _customerIds.toUuid(intoCustomerId);
    await client
        .from('sales')
        .update({'customer_id': intoUuid}).eq('customer_id', fromUuid);
    await client
        .from('loyalty_adjustments')
        .update({'customer_id': intoUuid}).eq('customer_id', fromUuid);
    // Best-effort: an older database that predates this table shouldn't
    // block the rest of the merge from completing.
    try {
      await client
          .from('customer_credits')
          .update({'customer_id': intoUuid}).eq('customer_id', fromUuid);
    } catch (_) {
      // Ignored - see comment above.
    }

    // customer_favorites has a (customer_id, product_id) primary key, so a
    // plain update could collide with a favorite the target already has -
    // copy over only what's missing, then drop the source's rows entirely.
    // Best-effort: an older database that predates this table shouldn't
    // block the merge's real work (sales/points already moved above) from
    // completing and archiving the duplicate customer.
    try {
      final fromFavorites = await client
          .from('customer_favorites')
          .select('product_id')
          .eq('customer_id', fromUuid);
      final intoFavorites = await client
          .from('customer_favorites')
          .select('product_id')
          .eq('customer_id', intoUuid);
      final intoProductIds =
          intoFavorites.map((r) => r['product_id'] as String).toSet();
      final newFavorites = fromFavorites
          .map((r) => r['product_id'] as String)
          .where((id) => !intoProductIds.contains(id))
          .map((id) => {'customer_id': intoUuid, 'product_id': id})
          .toList();
      if (newFavorites.isNotEmpty) {
        await client.from('customer_favorites').insert(newFavorites);
      }
      await client
          .from('customer_favorites')
          .delete()
          .eq('customer_id', fromUuid);
    } catch (_) {
      // Ignored - see comment above.
    }

    await client
        .from('customers')
        .update({'is_deleted': true}).eq('id', fromUuid);
  }

  @override
  Future<void> addCustomerFavorite(int customerId, int productId) async {
    await client.from('customer_favorites').upsert({
      'customer_id': _customerIds.toUuid(customerId),
      'product_id': _productIds.toUuid(productId),
    });
  }

  @override
  Future<void> removeCustomerFavorite(int customerId, int productId) async {
    await client
        .from('customer_favorites')
        .delete()
        .eq('customer_id', _customerIds.toUuid(customerId))
        .eq('product_id', _productIds.toUuid(productId));
  }
}
