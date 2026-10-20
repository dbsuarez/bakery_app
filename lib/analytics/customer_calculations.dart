import '../models/batch.dart';
import '../models/customer.dart';
import '../models/customer_credit.dart';
import '../models/loyalty_adjustment.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/money.dart';

/// Sum of a sale's non-deleted installment payments.
double salePaidAmount(int saleId, List<SalePayment> payments) {
  return sumMoney(
    payments
        .where((p) => p.saleId == saleId && !p.isDeleted)
        .map((p) => p.amount),
  );
}

/// How much of [sale] is still owed after any partial payments -
/// [sale.amount] itself never changes; partial payments just chip away at
/// what's outstanding until it flips to `paid`. Never negative.
double saleRemainingAmount(Sale sale, List<SalePayment> payments) {
  final remaining =
      toCentavos(sale.amount) - toCentavos(salePaidAmount(sale.id, payments));
  return remaining < 0 ? 0 : fromCentavos(remaining);
}

/// Spec section 7 rule 6: customer balances include only unpaid
/// customer_sale rows, net of any partial payments already received
/// against them.
double customerBalance(
  int customerId,
  List<Sale> sales, [
  List<SalePayment> payments = const [],
]) {
  return sumMoney(
    sales
        .where(
          (s) =>
              s.customerId == customerId &&
              !s.isDeleted &&
              !s.paid &&
              s.saleType == SaleType.customerSale,
        )
        .map((s) => saleRemainingAmount(s, payments)),
  );
}

/// A customer's running credit balance - positive means the bakery owes
/// them (e.g. an overpayment from a batch price correction), negative
/// would mean they owe a touch more (rare - a price increase after they'd
/// paid). See [CustomerCredit] for how entries are created.
double customerCreditBalance(int customerId, List<CustomerCredit> credits) {
  return sumMoney(
    credits
        .where((c) => c.customerId == customerId && !c.isDeleted)
        .map((c) => c.amount),
  );
}

int customerOrderCount(int customerId, List<Sale> sales) {
  return sales
      .where(
        (s) =>
            s.customerId == customerId &&
            !s.isDeleted &&
            s.saleType == SaleType.customerSale,
      )
      .length;
}

double customerTotalSpent(int customerId, List<Sale> sales) {
  return sumMoney(
    sales
        .where(
          (s) =>
              s.customerId == customerId &&
              !s.isDeleted &&
              s.saleType == SaleType.customerSale,
        )
        .map((s) => s.amount),
  );
}

/// Normal (non-pseudo, non-archived) customers, for loyalty/spending
/// leaderboards (spec section 7 rule 16).
List<Customer> normalCustomers(List<Customer> customers) {
  return customers.where((c) => !c.isPseudoCustomer && !c.isArchived).toList();
}

/// True if [sale] counts toward the loyalty program under [category].
/// A batch's "personal" flag only opts it out of remittance and business
/// revenue figures - a personal batch can still have real paying customers,
/// so it stays eligible for loyalty. Each product category keeps a fully
/// separate points pool - points earned buying Bakery items can't fund a
/// Merchandise redemption and vice versa.
bool _inLoyaltyCategory(
  Sale sale,
  ProductCategory category,
  Map<int, Batch> batchById,
  Map<int, Product> productById,
) {
  final batch = batchById[sale.batchId];
  if (batch == null) return false;
  final product = productById[batch.productId];
  return product != null && product.category == category;
}

/// Loyalty points earned from paid customer_sale rows: `amount / pesosPerPoint`,
/// with a same-day bonus multiplier when paid the same calendar day as the
/// sale (cash or otherwise - the bonus rewards speed of payment). The bonus
/// is withheld for sales dated before [sameDayBonusStartDate] - early
/// records were backfilled with a default payment date rather than the true
/// one, so they'd otherwise look like false same-day payments. Rounded down
/// so a customer is never credited more than they've actually earned.
int customerPointsEarned(
  int customerId,
  List<Sale> sales,
  List<Batch> batches,
  List<Product> products, {
  required ProductCategory category,
  required double pesosPerPoint,
  required double sameDayBonusPercent,
  required DateTime sameDayBonusStartDate,
}) {
  final batchById = {for (final b in batches) b.id: b};
  final productById = {for (final p in products) p.id: p};
  final paidSales = sales.where(
    (s) =>
        s.customerId == customerId &&
        !s.isDeleted &&
        s.paid &&
        s.saleType == SaleType.customerSale &&
        s.datePaid != null &&
        _inLoyaltyCategory(s, category, batchById, productById),
  );

  var total = 0.0;
  for (final s in paidSales) {
    var points = s.amount / pesosPerPoint;
    final sameDay =
        s.datePaid!.year == s.saleDate.year &&
        s.datePaid!.month == s.saleDate.month &&
        s.datePaid!.day == s.saleDate.day;
    final eligibleForBonus = !s.saleDate.isBefore(sameDayBonusStartDate);
    if (sameDay && eligibleForBonus) points *= 1 + sameDayBonusPercent / 100;
    total += points;
  }
  return total.floor();
}

/// Points spent redeeming products. Cost uses the redemption rate - a
/// separate, generally more generous conversion than the earn rate (e.g.
/// ₱25 spent earns 1 point, but 1 point is worth ₱1 toward a product) -
/// rounded up so a redemption never costs less than its peso value.
int customerPointsSpent(
  int customerId,
  List<Sale> sales,
  List<Batch> batches,
  List<Product> products, {
  required ProductCategory category,
  required double redeemPesosPerPoint,
}) {
  final batchById = {for (final b in batches) b.id: b};
  final productById = {for (final p in products) p.id: p};
  final redemptions = sales.where(
    (s) =>
        s.customerId == customerId &&
        !s.isDeleted &&
        s.saleType == SaleType.pointsRedemption &&
        _inLoyaltyCategory(s, category, batchById, productById),
  );

  var total = 0.0;
  for (final s in redemptions) {
    final unitPrice = batchById[s.batchId]?.unitPrice ?? 0;
    total += s.quantity * unitPrice / redeemPesosPerPoint;
  }
  return total.ceil();
}

/// Sum of manual point adjustments (goodwill credits, error fixes) for this
/// customer in this category - not tied to a real purchase.
int customerPointsAdjustment(
  int customerId,
  List<LoyaltyAdjustment> adjustments, {
  required ProductCategory category,
}) {
  return adjustments
      .where(
        (a) =>
            a.customerId == customerId &&
            !a.isDeleted &&
            a.category == category,
      )
      .fold(0, (sum, a) => sum + a.points);
}

int customerPointsBalance(
  int customerId,
  List<Sale> sales,
  List<Batch> batches,
  List<Product> products,
  List<LoyaltyAdjustment> adjustments, {
  required ProductCategory category,
  required double pesosPerPoint,
  required double sameDayBonusPercent,
  required double redeemPesosPerPoint,
  required DateTime sameDayBonusStartDate,
}) {
  final earned = customerPointsEarned(
    customerId,
    sales,
    batches,
    products,
    category: category,
    pesosPerPoint: pesosPerPoint,
    sameDayBonusPercent: sameDayBonusPercent,
    sameDayBonusStartDate: sameDayBonusStartDate,
  );
  final spent = customerPointsSpent(
    customerId,
    sales,
    batches,
    products,
    category: category,
    redeemPesosPerPoint: redeemPesosPerPoint,
  );
  final adjustment = customerPointsAdjustment(
    customerId,
    adjustments,
    category: category,
  );
  return earned - spent + adjustment;
}

/// Points cost to redeem [quantity] units of a batch at its unit price,
/// converted at the redemption rate (not the earn rate).
int pointsCostForBatch(
  Batch batch,
  int quantity, {
  required double redeemPesosPerPoint,
}) {
  return (quantity * batch.unitPrice / redeemPesosPerPoint).ceil();
}
