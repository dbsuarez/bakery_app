import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/batch.dart' as m;
import '../models/cash_advance.dart' as m;
import '../models/customer.dart' as m;
import '../models/customer_credit.dart' as m;
import '../models/customer_favorite.dart' as m;
import '../models/expense.dart' as m;
import '../models/favorite_dismissal.dart' as m;
import '../models/loyalty_adjustment.dart' as m;
import '../models/product.dart' as m;
import '../models/sale.dart' as m;
import '../utils/money.dart';
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

/// Enforces the app's settled-accounting rule before a transaction or batch
/// mutation is sent. PostgreSQL triggers/RPCs repeat this check authoritatively.
void ensureBatchTransactionsMutable({required bool locked}) {
  if (locked) {
    throw StateError(
      'Transactions in a locked batch cannot be changed. Unlock the batch '
      'first.',
    );
  }
}

class _RemoteSnapshot {
  final Map<String, List<Map<String, dynamic>>> tables;

  const _RemoteSnapshot(this.tables);

  List<Map<String, dynamic>> operator [](String table) =>
      tables[table] ?? const [];
}

class RemoteRepository implements BakeryRepository {
  static const _pollInterval = Duration(seconds: 30);

  final SupabaseClient client;
  late final Stream<_RemoteSnapshot> _snapshots;
  int _refreshVersion = 0;
  final Set<Completer<void>> _refreshWaiters = {};

  /// Set whenever a background poll fails - surfaced in Settings so a
  /// silent connectivity problem (data just stops updating) is visible
  /// instead of the app quietly showing stale/empty data forever.
  final ValueNotifier<String?> lastFetchError = ValueNotifier(null);

  /// Diagnostic: what the last successful poll of each table actually
  /// returned (row count + when), so an unexpected "0 rows" (RLS/auth
  /// mismatch) is distinguishable from "poll never ran at all".
  final ValueNotifier<Map<String, String>> lastFetchInfo = ValueNotifier({});
  final ValueNotifier<bool> isFetching = ValueNotifier(false);

  final _productIds = _IdMapper();
  final _customerIds = _IdMapper();
  final _batchIds = _IdMapper();
  final _saleIds = _IdMapper();
  final _loyaltyAdjustmentIds = _IdMapper();
  final _salePaymentIds = _IdMapper();
  final _customerCreditIds = _IdMapper();
  final _expenseIds = _IdMapper();
  final _cashAdvanceIds = _IdMapper();
  final _cashAdvancePaymentIds = _IdMapper();

  RemoteRepository(this.client) {
    // All ten consumers subscribe during AppState construction. A broadcast
    // stream lets them share one RPC request and one polling timer.
    _snapshots = _watchSnapshots().asBroadcastStream();
  }

  @override
  void refresh() {
    _refreshVersion++;
    final waiters = _refreshWaiters.toList();
    _refreshWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  Future<void> _waitForRefresh(int observedVersion) async {
    if (_refreshVersion != observedVersion) return;
    final waiter = Completer<void>();
    _refreshWaiters.add(waiter);
    try {
      await waiter.future.timeout(_pollInterval, onTimeout: () {});
    } finally {
      _refreshWaiters.remove(waiter);
    }
  }

  m.Product _productFromRow(Map<String, dynamic> row) => m.Product(
    id: _productIds.toInt(row['id'] as String),
    remoteId: row['id'] as String,
    title: row['title'] as String,
    imageUrl: row['image_url'] as String?,
    category: m.ProductCategory.fromValue(
      row['category'] as String? ?? 'bakery',
    ),
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
    isReservation: row['is_reservation'] as bool? ?? false,
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

  m.SalePayment _salePaymentFromRow(Map<String, dynamic> row) => m.SalePayment(
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

  m.FavoriteDismissal _favoriteDismissalFromRow(Map<String, dynamic> row) =>
      m.FavoriteDismissal(
        customerId: _customerIds.toInt(row['customer_id'] as String),
        batchId: _batchIds.toInt(row['batch_id'] as String),
      );

  m.Expense _expenseFromRow(Map<String, dynamic> row) => m.Expense(
    id: _expenseIds.toInt(row['id'] as String),
    remoteId: row['id'] as String,
    amount: (row['amount'] as num).toDouble(),
    category: row['category'] as String? ?? 'Other',
    expenseDate: DateTime.parse(row['expense_date'] as String),
    notes: row['notes'] as String?,
    updatedAt: DateTime.parse(row['updated_at'] as String),
    isDirty: false,
    isDeleted: row['is_deleted'] as bool,
  );

  m.CashAdvance _cashAdvanceFromRow(Map<String, dynamic> row) => m.CashAdvance(
    id: _cashAdvanceIds.toInt(row['id'] as String),
    remoteId: row['id'] as String,
    customerId: _customerIds.toInt(row['customer_id'] as String),
    advanceDate: DateTime.parse(row['advance_date'] as String),
    amount: (row['amount'] as num).toDouble(),
    paid: row['paid'] as bool? ?? false,
    datePaid: row['date_paid'] == null
        ? null
        : DateTime.parse(row['date_paid'] as String),
    paymentMethod: row['payment_method'] as String?,
    notes: row['notes'] as String?,
    updatedAt: DateTime.parse(row['updated_at'] as String),
    isDeleted: row['is_deleted'] as bool? ?? false,
  );

  m.CashAdvancePayment _cashAdvancePaymentFromRow(Map<String, dynamic> row) =>
      m.CashAdvancePayment(
        id: _cashAdvancePaymentIds.toInt(row['id'] as String),
        remoteId: row['id'] as String,
        cashAdvanceId: _cashAdvanceIds.toInt(row['cash_advance_id'] as String),
        amount: (row['amount'] as num).toDouble(),
        paymentDate: DateTime.parse(row['payment_date'] as String),
        paymentMethod: row['payment_method'] as String?,
        notes: row['notes'] as String?,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        isDeleted: row['is_deleted'] as bool? ?? false,
      );

  Future<void> _ensureBatchUnlocked(String batchUuid) async {
    final batch = await client
        .from('batches')
        .select('locked')
        .eq('id', batchUuid)
        .single();
    ensureBatchTransactionsMutable(locked: batch['locked'] as bool? ?? false);
  }

  Future<void> _ensureSaleUnlocked(int saleId) async {
    final sale = await client
        .from('sales')
        .select('batch_id')
        .eq('id', _saleIds.toUuid(saleId))
        .single();
    await _ensureBatchUnlocked(sale['batch_id'] as String);
  }

  static const _snapshotTables = <String>[
    'products',
    'customers',
    'batches',
    'sales',
    'loyalty_adjustments',
    'sale_payments',
    'customer_credits',
    'customer_favorites',
    'favorite_dismissals',
    'expenses',
    'cash_advances',
    'cash_advance_payments',
  ];

  List<Map<String, dynamic>> _snapshotRows(
    Map<String, dynamic> snapshot,
    String table,
  ) {
    final value = snapshot[table];
    if (value is! List) {
      throw FormatException('Snapshot field "$table" is not a list.');
    }
    return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  // Realtime's `.stream()` depends on a long-lived WebSocket connection.
  // Keep the resilient REST fallback, but fetch one consistent snapshot via
  // one RPC instead of issuing ten independent table requests.
  Stream<_RemoteSnapshot> _watchSnapshots() async* {
    while (true) {
      final observedVersion = _refreshVersion;
      try {
        isFetching.value = true;
        final response = await client
            .rpc('get_app_snapshot')
            .timeout(const Duration(seconds: 15));
        final snapshot = Map<String, dynamic>.from(response as Map);
        final tables = <String, List<Map<String, dynamic>>>{
          for (final table in _snapshotTables)
            table: _snapshotRows(snapshot, table),
        };
        lastFetchError.value = null;
        final now = DateTime.now();
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        final ss = now.second.toString().padLeft(2, '0');
        lastFetchInfo.value = {
          for (final entry in tables.entries)
            entry.key: '${entry.value.length} rows @ $hh:$mm:$ss',
        };
        yield _RemoteSnapshot(tables);
      } catch (e) {
        // Keep the stream alive on a transient failure; the UI just keeps
        // showing the last successfully-fetched values.
        lastFetchError.value = 'snapshot: $e';
      } finally {
        isFetching.value = false;
      }
      // Refresh promptly after a successful mutation or app resume. The
      // timeout is the low-frequency fallback for changes made elsewhere.
      await _waitForRefresh(observedVersion);
    }
  }

  @override
  Stream<List<m.Product>> watchProducts() {
    return _snapshots.map(
      (snapshot) => snapshot['products'].map(_productFromRow).toList(),
    );
  }

  @override
  Stream<List<m.Customer>> watchCustomers() {
    return _snapshots.map(
      (snapshot) => snapshot['customers'].map(_customerFromRow).toList(),
    );
  }

  @override
  Stream<List<m.Batch>> watchBatches() {
    return _snapshots.map(
      (snapshot) => snapshot['batches'].map(_batchFromRow).toList(),
    );
  }

  @override
  Stream<List<m.Sale>> watchSales() {
    return _snapshots.map(
      (snapshot) => snapshot['sales'].map(_saleFromRow).toList(),
    );
  }

  @override
  Stream<List<m.LoyaltyAdjustment>> watchLoyaltyAdjustments() {
    return _snapshots.map(
      (snapshot) => snapshot['loyalty_adjustments']
          .map(_loyaltyAdjustmentFromRow)
          .toList(),
    );
  }

  @override
  Stream<List<m.SalePayment>> watchSalePayments() {
    return _snapshots.map(
      (snapshot) => snapshot['sale_payments'].map(_salePaymentFromRow).toList(),
    );
  }

  @override
  Stream<List<m.CustomerCredit>> watchCustomerCredits() {
    return _snapshots.map(
      (snapshot) =>
          snapshot['customer_credits'].map(_customerCreditFromRow).toList(),
    );
  }

  @override
  Stream<List<m.CustomerFavorite>> watchCustomerFavorites() {
    return _snapshots.map(
      (snapshot) =>
          snapshot['customer_favorites'].map(_customerFavoriteFromRow).toList(),
    );
  }

  @override
  Stream<List<m.FavoriteDismissal>> watchFavoriteDismissals() {
    return _snapshots.map(
      (snapshot) => snapshot['favorite_dismissals']
          .map(_favoriteDismissalFromRow)
          .toList(),
    );
  }

  @override
  Stream<List<m.Expense>> watchExpenses() {
    return _snapshots.map(
      (snapshot) => snapshot['expenses'].map(_expenseFromRow).toList(),
    );
  }

  @override
  Stream<List<m.CashAdvance>> watchCashAdvances() => _snapshots.map(
    (snapshot) => snapshot['cash_advances'].map(_cashAdvanceFromRow).toList(),
  );

  @override
  Stream<List<m.CashAdvancePayment>> watchCashAdvancePayments() =>
      _snapshots.map(
        (snapshot) => snapshot['cash_advance_payments']
            .map(_cashAdvancePaymentFromRow)
            .toList(),
      );

  @override
  Future<void> createProduct(m.Product product) async {
    await client.from('products').insert({
      'title': product.title,
      'image_url': product.imageUrl,
      'category': product.category.value,
    });
    refresh();
  }

  @override
  Future<void> updateProduct(m.Product product) async {
    await client
        .from('products')
        .update({
          'title': product.title,
          'image_url': product.imageUrl,
          'category': product.category.value,
          'is_archived': product.isArchived,
        })
        .eq('id', _productIds.toUuid(product.id));
    refresh();
  }

  @override
  Future<void> createCustomer(m.Customer customer) async {
    await client.from('customers').insert({
      'name': customer.name,
      'phone': customer.phone,
      'group_name': customer.group,
    });
    refresh();
  }

  @override
  Future<void> updateCustomer(m.Customer customer) async {
    await client
        .from('customers')
        .update({
          'name': customer.name,
          'phone': customer.phone,
          'is_archived': customer.isArchived,
          'group_name': customer.group,
        })
        .eq('id', _customerIds.toUuid(customer.id));
    refresh();
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
    refresh();
  }

  @override
  Future<void> updateBatch(m.Batch batch) async {
    final uuid = _batchIds.toUuid(batch.id);
    await _ensureBatchUnlocked(uuid);
    await client
        .from('batches')
        .update({
          'product_id': _productIds.toUuid(batch.productId),
          'batch_date': _dateOnly(batch.batchDate),
          'count_produced': batch.countProduced,
          'unit_price': batch.unitPrice,
          'unit_cost': batch.unitCost,
          'total_value': batch.countProduced * batch.unitPrice,
          'is_personal': batch.isPersonal,
        })
        .eq('id', uuid);
    refresh();
  }

  @override
  Future<void> addSingleSale(m.Sale sale) async {
    if (sale.quantity <= 0) {
      throw ArgumentError('Quantity must be a positive integer.');
    }
    await client.rpc(
      'create_sale_atomic',
      params: {
        'p_batch_id': _batchIds.toUuid(sale.batchId),
        'p_customer_id': _customerIds.toUuid(sale.customerId),
        'p_sale_date': _dateOnly(sale.saleDate),
        'p_quantity': sale.quantity,
        'p_amount': sale.amount,
        'p_discount': sale.discount,
        'p_paid': sale.paid,
        'p_date_paid': sale.datePaid == null ? null : _dateOnly(sale.datePaid!),
        'p_payment_method': sale.paymentMethod,
        'p_sale_type': sale.saleType.value,
        'p_notes': sale.notes,
        'p_is_reservation': sale.isReservation,
      },
    );
    refresh();
  }

  @override
  Future<void> updateSale(m.Sale sale, {bool allowOverallocate = false}) async {
    if (sale.quantity <= 0) {
      throw ArgumentError('Quantity must be a positive integer.');
    }
    await client.rpc(
      'update_sale_atomic',
      params: {
        'p_sale_id': _saleIds.toUuid(sale.id),
        'p_batch_id': _batchIds.toUuid(sale.batchId),
        'p_customer_id': _customerIds.toUuid(sale.customerId),
        'p_sale_date': _dateOnly(sale.saleDate),
        'p_quantity': sale.quantity,
        'p_amount': sale.amount,
        'p_discount': sale.discount,
        'p_paid': sale.paid,
        'p_date_paid': sale.datePaid == null ? null : _dateOnly(sale.datePaid!),
        'p_payment_method': sale.paymentMethod,
        'p_sale_type': sale.saleType.value,
        'p_notes': sale.notes,
        'p_is_reservation': sale.isReservation,
        'p_allow_overallocate': allowOverallocate,
      },
    );
    refresh();
  }

  @override
  Future<void> addBatchTransactions(
    int batchId,
    List<m.BatchTransactionEntry> entries, {
    bool allowOverallocate = false,
  }) async {
    if (entries.isEmpty) return;
    for (final entry in entries) {
      if (entry.quantity <= 0) {
        throw ArgumentError('Quantity must be a positive integer.');
      }
    }
    final now = _dateOnly(DateTime.now());
    await client.rpc(
      'create_batch_sales_atomic',
      params: {
        'p_batch_id': _batchIds.toUuid(batchId),
        'p_entries': [
          for (final entry in entries)
            {
              'customer_id': _customerIds.toUuid(entry.customerId),
              'sale_date': now,
              'quantity': entry.quantity,
              'amount': entry.amount,
              'discount': entry.discount,
              'paid': entry.paid,
              'date_paid': entry.datePaid == null
                  ? null
                  : _dateOnly(entry.datePaid!),
              'payment_method': entry.paymentMethod,
              'notes': entry.notes,
              'is_reservation': entry.isReservation,
            },
        ],
        'p_allow_overallocate': allowOverallocate,
      },
    );
    refresh();
  }

  @override
  Future<void> addSalePayment(m.SalePayment payment) async {
    if (payment.amount <= 0) {
      throw ArgumentError('Payment amount must be positive.');
    }
    await _ensureSaleUnlocked(payment.saleId);
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
    final totalPaid = sumMoney(
      existingPayments.map((row) => row['amount'] as num),
    );
    if (toCentavos(totalPaid) >= toCentavos(saleAmount)) {
      await client
          .from('sales')
          .update({
            'paid': true,
            'date_paid': _dateOnly(payment.paymentDate),
            'payment_method': payment.paymentMethod,
          })
          .eq('id', saleUuid);
    }
    refresh();
  }

  @override
  Future<void> createCashAdvance(m.CashAdvance cashAdvance) async {
    if (cashAdvance.amount <= 0) {
      throw ArgumentError('Cash advance amount must be positive.');
    }
    await client.from('cash_advances').insert({
      'customer_id': _customerIds.toUuid(cashAdvance.customerId),
      'advance_date': _dateOnly(cashAdvance.advanceDate),
      'amount': cashAdvance.amount,
      'paid': cashAdvance.paid,
      'date_paid': cashAdvance.datePaid == null
          ? null
          : _dateOnly(cashAdvance.datePaid!),
      'payment_method': cashAdvance.paymentMethod,
      'notes': cashAdvance.notes,
    });
    refresh();
  }

  @override
  Future<void> updateCashAdvance(m.CashAdvance cashAdvance) async {
    if (cashAdvance.amount <= 0) {
      throw ArgumentError('Cash advance amount must be positive.');
    }
    await client
        .from('cash_advances')
        .update({
          'advance_date': _dateOnly(cashAdvance.advanceDate),
          'amount': cashAdvance.amount,
          'notes': cashAdvance.notes,
        })
        .eq('id', _cashAdvanceIds.toUuid(cashAdvance.id));
    refresh();
  }

  @override
  Future<void> deleteCashAdvance(int cashAdvanceId) async {
    await client
        .from('cash_advances')
        .update({'is_deleted': true})
        .eq('id', _cashAdvanceIds.toUuid(cashAdvanceId));
    refresh();
  }

  @override
  Future<void> addCashAdvancePayment(m.CashAdvancePayment payment) async {
    if (payment.amount <= 0) {
      throw ArgumentError('Payment amount must be positive.');
    }
    await client.rpc(
      'record_cash_advance_payment',
      params: {
        'p_cash_advance_id': _cashAdvanceIds.toUuid(payment.cashAdvanceId),
        'p_amount': payment.amount,
        'p_payment_date': _dateOnly(payment.paymentDate),
        'p_payment_method': payment.paymentMethod,
        'p_notes': payment.notes,
      },
    );
    refresh();
  }

  @override
  Future<void> markCashAdvancePaid(
    int cashAdvanceId,
    DateTime paymentDate, {
    String? paymentMethod,
  }) async {
    await client
        .from('cash_advances')
        .update({
          'paid': true,
          'date_paid': _dateOnly(paymentDate),
          'payment_method': paymentMethod,
        })
        .eq('id', _cashAdvanceIds.toUuid(cashAdvanceId));
    refresh();
  }

  @override
  Future<void> markCashAdvanceUnpaid(int cashAdvanceId) async {
    await client
        .from('cash_advances')
        .update({'paid': false, 'date_paid': null, 'payment_method': null})
        .eq('id', _cashAdvanceIds.toUuid(cashAdvanceId));
    refresh();
  }

  @override
  Future<void> markSalePaid(
    int saleId,
    DateTime paymentDate, {
    String? paymentMethod,
  }) async {
    await _ensureSaleUnlocked(saleId);
    await client
        .from('sales')
        .update({
          'paid': true,
          'date_paid': _dateOnly(paymentDate),
          'payment_method': paymentMethod,
        })
        .eq('id', _saleIds.toUuid(saleId));
    refresh();
  }

  @override
  Future<void> markSaleUnpaid(int saleId) async {
    await _ensureSaleUnlocked(saleId);
    await client
        .from('sales')
        .update({'paid': false, 'date_paid': null})
        .eq('id', _saleIds.toUuid(saleId));
    refresh();
  }

  @override
  Future<void> markBatchRemitted(int batchId, DateTime dateRemitted) async {
    await client
        .from('batches')
        .update({
          'remitted': true,
          'date_remitted': _dateOnly(dateRemitted),
          'locked': true,
        })
        .eq('id', _batchIds.toUuid(batchId));
    refresh();
  }

  @override
  Future<void> unlockBatch(int batchId) async {
    await client
        .from('batches')
        .update({'locked': false})
        .eq('id', _batchIds.toUuid(batchId));
    refresh();
  }

  @override
  Future<void> lockBatch(int batchId) async {
    await client
        .from('batches')
        .update({'locked': true})
        .eq('id', _batchIds.toUuid(batchId));
    refresh();
  }

  @override
  Future<void> revertBatchRemittance(int batchId) async {
    await client
        .from('batches')
        .update({'remitted': false, 'date_remitted': null, 'locked': false})
        .eq('id', _batchIds.toUuid(batchId));
    refresh();
  }

  @override
  Future<void> deleteSale(int saleId) async {
    await _ensureSaleUnlocked(saleId);
    await client
        .from('sales')
        .update({'is_deleted': true})
        .eq('id', _saleIds.toUuid(saleId));
    refresh();
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
    refresh();
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
    refresh();
  }

  @override
  Future<void> reconcileBatchUnitPrice(
    int batchId,
    double oldUnitPrice,
    double newUnitPrice,
  ) async {
    final batchUuid = _batchIds.toUuid(batchId);
    await _ensureBatchUnlocked(batchUuid);
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
            'reason':
                'Batch unit price corrected from '
                '₱${oldUnitPrice.toStringAsFixed(2)} to '
                '₱${newUnitPrice.toStringAsFixed(2)}',
            'sale_id': saleUuid,
          });
        }
      }
      await client
          .from('sales')
          .update({'amount': newAmount})
          .eq('id', saleUuid);
    }
    refresh();
  }

  @override
  Future<void> mergeCustomers(int fromCustomerId, int intoCustomerId) async {
    final fromUuid = _customerIds.toUuid(fromCustomerId);
    final intoUuid = _customerIds.toUuid(intoCustomerId);
    await client
        .from('sales')
        .update({'customer_id': intoUuid})
        .eq('customer_id', fromUuid);
    await client
        .from('loyalty_adjustments')
        .update({'customer_id': intoUuid})
        .eq('customer_id', fromUuid);
    // Best-effort: an older database that predates this table shouldn't
    // block the rest of the merge from completing.
    try {
      await client
          .from('customer_credits')
          .update({'customer_id': intoUuid})
          .eq('customer_id', fromUuid);
    } catch (_) {
      // Ignored - see comment above.
    }
    try {
      await client
          .from('cash_advances')
          .update({'customer_id': intoUuid})
          .eq('customer_id', fromUuid);
    } catch (_) {
      // Older databases may not have cash advances yet.
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
      final intoProductIds = intoFavorites
          .map((r) => r['product_id'] as String)
          .toSet();
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
        .update({'is_deleted': true})
        .eq('id', fromUuid);
    refresh();
  }

  @override
  Future<void> addCustomerFavorite(int customerId, int productId) async {
    await client.from('customer_favorites').upsert({
      'customer_id': _customerIds.toUuid(customerId),
      'product_id': _productIds.toUuid(productId),
    });
    refresh();
  }

  @override
  Future<void> removeCustomerFavorite(int customerId, int productId) async {
    await client
        .from('customer_favorites')
        .delete()
        .eq('customer_id', _customerIds.toUuid(customerId))
        .eq('product_id', _productIds.toUuid(productId));
    refresh();
  }

  @override
  Future<void> dismissFavorite(int customerId, int batchId) async {
    await client.from('favorite_dismissals').upsert({
      'customer_id': _customerIds.toUuid(customerId),
      'batch_id': _batchIds.toUuid(batchId),
    });
    refresh();
  }

  @override
  Future<void> addExpense(m.Expense expense) async {
    if (expense.amount <= 0) {
      throw ArgumentError('Expense amount must be positive.');
    }
    await client.from('expenses').insert({
      'amount': expense.amount,
      'category': expense.category,
      'expense_date': _dateOnly(expense.expenseDate),
      'notes': expense.notes,
    });
    refresh();
  }

  @override
  Future<void> updateExpense(m.Expense expense) async {
    if (expense.amount <= 0) {
      throw ArgumentError('Expense amount must be positive.');
    }
    await client
        .from('expenses')
        .update({
          'amount': expense.amount,
          'category': expense.category,
          'expense_date': _dateOnly(expense.expenseDate),
          'notes': expense.notes,
        })
        .eq('id', _expenseIds.toUuid(expense.id));
    refresh();
  }

  @override
  Future<void> deleteExpense(int expenseId) async {
    await client
        .from('expenses')
        .update({'is_deleted': true})
        .eq('id', _expenseIds.toUuid(expenseId));
    refresh();
  }
}
