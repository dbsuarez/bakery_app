import 'package:bakery_app/analytics/batch_calculations.dart';
import 'package:bakery_app/analytics/customer_calculations.dart';
import 'package:bakery_app/analytics/dashboard_analytics.dart';
import 'package:bakery_app/models/batch.dart';
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

    test('overpayment never creates a negative outstanding balance', () {
      final sale = _sale(1, batchId: 1, amount: 100);
      expect(
        saleRemainingAmount(sale, [_payment(1, saleId: 1, amount: 125)]),
        0,
      );
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
}) => Batch(
  id: id,
  productId: productId,
  batchDate: date,
  countProduced: produced,
  unitPrice: unitPrice,
  unitCost: unitCost,
  totalValue: produced * unitPrice,
  updatedAt: date,
);

Sale _sale(
  int id, {
  required int batchId,
  int quantity = 1,
  double amount = 0,
  SaleType type = SaleType.customerSale,
  bool paid = false,
  DateTime? datePaid,
  bool deleted = false,
}) => Sale(
  id: id,
  batchId: batchId,
  customerId: 1,
  saleDate: DateTime(2026, 10, 19),
  quantity: quantity,
  amount: amount,
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
