import 'package:bakery_app/analytics/batch_calculations.dart';
import 'package:bakery_app/analytics/customer_calculations.dart';
import 'package:bakery_app/analytics/dashboard_analytics.dart';
import 'package:bakery_app/models/batch.dart';
import 'package:bakery_app/models/cash_advance.dart';
import 'package:bakery_app/models/customer.dart';
import 'package:bakery_app/models/expense.dart';
import 'package:bakery_app/models/loyalty_adjustment.dart';
import 'package:bakery_app/models/product.dart';
import 'package:bakery_app/models/sale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 19, 12);

  group('inventory allocation', () {
    test('counts allocations and ignores unsold and deleted rows', () {
      final sales = [
        _sale(1, batchId: 1, quantity: 2),
        _sale(2, batchId: 1, quantity: 3, type: SaleType.internalConsumption),
        _sale(3, batchId: 1, quantity: 1, type: SaleType.pointsRedemption),
        _sale(4, batchId: 1, quantity: 20, type: SaleType.unsold),
        _sale(5, batchId: 1, quantity: 20, deleted: true),
      ];

      expect(allocatedQuantity(1, sales), 6);
      expect(remainingQuantity(_batch(now, produced: 10), sales), 4);
    });
  });

  group('partial payments', () {
    test('reduces the balance by live installments', () {
      final sale = _sale(1, batchId: 1, amount: 100);
      final payments = [
        _payment(1, saleId: 1, amount: 30),
        _payment(2, saleId: 1, amount: 20),
        _payment(3, saleId: 1, amount: 40, deleted: true),
      ];

      expect(salePaidAmount(1, payments), 50);
      expect(saleRemainingAmount(sale, payments), 50);
      expect(customerBalance(1, [sale], payments), 50);
    });

    test('cash advances and installments are included in customer balance', () {
      final advance = CashAdvance(
        id: 10,
        customerId: 1,
        advanceDate: now,
        amount: 500,
        updatedAt: now,
      );
      final payments = [
        CashAdvancePayment(
          id: 11,
          cashAdvanceId: 10,
          amount: 125,
          paymentDate: now,
          updatedAt: now,
        ),
      ];

      expect(cashAdvancePaidAmount(10, payments), 125);
      expect(cashAdvanceRemainingAmount(advance, payments), 375);
      expect(customerBalance(1, const [], const [], [advance], payments), 375);
    });

    test('overpayment never creates a negative outstanding balance', () {
      final sale = _sale(1, batchId: 1, amount: 100);
      expect(
        saleRemainingAmount(sale, [_payment(1, saleId: 1, amount: 125)]),
        0,
      );
    });

    test('breakdown separates bakery and personal batch balances', () {
      final result = customerBalanceBreakdown(
        1,
        [_sale(1, batchId: 1, amount: 100), _sale(2, batchId: 2, amount: 60)],
        [_batch(now, id: 1), _batch(now, id: 2, isPersonal: true)],
        [_payment(1, saleId: 1, amount: 25)],
      );

      expect(result.bakery, 75);
      expect(result.personal, 60);
    });
  });

  test('month boundaries include the first day and exclude prior expenses', () {
    final data = computeDashboard(
      products: const [],
      customers: const [],
      batches: [_batch(DateTime(2026, 10, 1), unitCost: 4)],
      sales: const [],
      expenses: [
        _expense(1, DateTime(2026, 9, 30), 90),
        _expense(2, DateTime(2026, 10, 1), 10),
        _expense(3, DateTime(2026, 10, 19), 5),
        _expense(4, DateTime(2026, 10, 19), 100, deleted: true),
      ],
      now: now,
    );

    expect(data.thisMonthExpenses, 15);
    expect(data.allTimeExpenses, 105);
    expect(data.thisMonthEstimatedProfit, 60);
    expect(data.thisMonthNetProfit, 45);
  });

  test('pending remittance uses the full batch value', () {
    final data = computeDashboard(
      products: const [],
      customers: const [],
      batches: [_batch(now, produced: 10, unitPrice: 10)],
      sales: [_sale(1, batchId: 1, amount: 10)],
      now: now,
    );

    expect(data.pendingRemittance, 100);
  });

  test('internal use is valued at unit price and deducted from remittance', () {
    final batch = _batch(now, produced: 10, unitPrice: 10);
    final sales = [
      _sale(1, batchId: 1, amount: 30),
      _sale(
        2,
        batchId: 1,
        quantity: 2,
        amount: 5,
        type: SaleType.internalConsumption,
      ),
    ];

    expect(batchInternalConsumptionValue(batch, sales), 20);
    expect(batchRemittanceValue(batch, sales), 80);
    expect(batchRecordedCustomerTransactions(1, sales), 30);
    final data = computeDashboard(
      products: const [],
      customers: const [],
      batches: [batch],
      sales: sales,
      now: now,
    );
    expect(data.pendingRemittance, 80);
  });

  test('manually recorded discounts reduce remittance', () {
    final batch = _batch(now, produced: 10, unitPrice: 10);
    final sales = [_sale(1, batchId: 1, quantity: 2, amount: 15, discount: 5)];

    expect(batchApprovedDiscountValue(batch, sales), 5);
    expect(batchRemittanceValue(batch, sales), 95);
  });

  test('manually recorded add-ons increase remittance', () {
    final batch = _batch(now, produced: 10, unitPrice: 10);
    final sales = [_sale(1, batchId: 1, quantity: 1, amount: 15, discount: -5)];

    expect(batchApprovedAddOnValue(batch, sales), 5);
    expect(batchRemittanceValue(batch, sales), 105);
  });

  test('customer of the month is separate from customer of all time', () {
    final customers = [
      Customer(id: 1, name: 'All-time winner', updatedAt: now),
      Customer(id: 2, name: 'October winner', updatedAt: now),
    ];
    final data = computeDashboard(
      products: const [],
      customers: customers,
      batches: [_batch(now), _batch(now, id: 2, isPersonal: true)],
      sales: [
        _sale(
          1,
          batchId: 1,
          customerId: 1,
          amount: 1000,
          saleDate: DateTime(2026, 9, 30),
        ),
        _sale(2, batchId: 1, customerId: 1, amount: 50),
        _sale(3, batchId: 2, customerId: 2, amount: 200),
      ],
      now: now,
    );

    expect(data.customerOfTheMonth?.name, 'October winner');
    expect(data.customerOfAllTime?.name, 'All-time winner');
    expect(data.monthlyCustomerWinners.length, 2);
    expect(data.monthlyCustomerWinners.first.customer.name, 'October winner');
    expect(data.monthlyCustomerWinners.first.amount, 200);
    expect(data.monthlyCustomerWinners.last.customer.name, 'All-time winner');
    expect(data.monthlyCustomerWinners.last.amount, 1000);
    expect(data.topSpenders.firstWhere((s) => s.customer.id == 2).value, 200);
    expect(
      data.topUnpaidBalances.firstWhere((s) => s.customer.id == 2).value,
      200,
    );
  });

  test('dashboard unpaid balance matches bakery plus personal breakdown', () {
    final batches = [_batch(now, id: 1), _batch(now, id: 2, isPersonal: true)];
    final sales = [
      _sale(1, batchId: 1, amount: 100),
      _sale(2, batchId: 2, amount: 60),
    ];
    final advances = [
      CashAdvance(
        id: 1,
        customerId: 1,
        advanceDate: now,
        amount: 40,
        updatedAt: now,
      ),
    ];
    final customer = Customer(id: 1, name: 'Customer', updatedAt: now);
    final breakdown = customerBalanceBreakdown(
      1,
      sales,
      batches,
      const [],
      advances,
    );
    final dashboard = computeDashboard(
      products: const [],
      customers: [customer],
      batches: batches,
      sales: sales,
      cashAdvances: advances,
      now: now,
    );

    expect(breakdown.bakery, 100);
    expect(breakdown.personal, 100);
    expect(dashboard.outstandingReceivables, breakdown.bakery);
    expect(dashboard.personalOutstandingReceivables, breakdown.personal);
    expect(dashboard.topUnpaidBalances.single.value, 200);
    expect(
      dashboard.topUnpaidBalances.single.value,
      breakdown.bakery + breakdown.personal,
    );
  });

  test(
    'loyalty keeps categories separate and applies redemption/adjustment',
    () {
      final bakery = Product(
        id: 1,
        title: 'Bread',
        updatedAt: now,
        category: ProductCategory.bakery,
      );
      final merchandise = Product(
        id: 2,
        title: 'Bag',
        updatedAt: now,
        category: ProductCategory.merchandise,
      );
      final batches = [
        _batch(now, id: 1, productId: 1, unitPrice: 25),
        _batch(now, id: 2, productId: 2, unitPrice: 100),
      ];
      final sales = [
        _sale(1, batchId: 1, amount: 100, paid: true, datePaid: now),
        _sale(2, batchId: 2, amount: 100, paid: true, datePaid: now),
        _sale(3, batchId: 1, quantity: 2, type: SaleType.pointsRedemption),
      ];
      final adjustments = [
        LoyaltyAdjustment(
          id: 1,
          customerId: 1,
          category: ProductCategory.bakery,
          points: 3,
          adjustmentDate: now,
          updatedAt: now,
        ),
      ];

      expect(
        customerPointsBalance(
          1,
          sales,
          batches,
          [bakery, merchandise],
          adjustments,
          category: ProductCategory.bakery,
          pesosPerPoint: 25,
          sameDayBonusPercent: 25,
          redeemPesosPerPoint: 1,
          sameDayBonusStartDate: DateTime(2026),
        ),
        -42,
      ); // 5 earned - 50 redeemed + 3 adjustment.
    },
  );
}

Batch _batch(
  DateTime date, {
  int id = 1,
  int productId = 1,
  int produced = 10,
  double unitPrice = 10,
  double unitCost = 0,
  bool isPersonal = false,
}) => Batch(
  id: id,
  productId: productId,
  batchDate: date,
  countProduced: produced,
  unitPrice: unitPrice,
  unitCost: unitCost,
  totalValue: produced * unitPrice,
  isPersonal: isPersonal,
  updatedAt: date,
);

Sale _sale(
  int id, {
  required int batchId,
  int customerId = 1,
  int quantity = 1,
  double amount = 0,
  SaleType type = SaleType.customerSale,
  bool paid = false,
  DateTime? datePaid,
  DateTime? saleDate,
  bool deleted = false,
  double discount = 0,
}) => Sale(
  id: id,
  batchId: batchId,
  customerId: customerId,
  saleDate: saleDate ?? DateTime(2026, 10, 19),
  quantity: quantity,
  amount: amount,
  discount: discount,
  paid: paid,
  datePaid: datePaid,
  saleType: type,
  updatedAt: DateTime(2026, 10, 19),
  isDeleted: deleted,
);

SalePayment _payment(
  int id, {
  required int saleId,
  required double amount,
  bool deleted = false,
}) => SalePayment(
  id: id,
  saleId: saleId,
  amount: amount,
  paymentDate: DateTime(2026, 10, 19),
  updatedAt: DateTime(2026, 10, 19),
  isDeleted: deleted,
);

Expense _expense(
  int id,
  DateTime date,
  double amount, {
  bool deleted = false,
}) => Expense(
  id: id,
  amount: amount,
  expenseDate: date,
  updatedAt: date,
  isDeleted: deleted,
);
