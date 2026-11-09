import '../models/batch.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/money.dart';

/// Spec section 7 rule 7: batch remaining quantity = produced quantity -
/// allocated quantity. Real customer sales, internal consumption
/// (freebies/samples eaten by the owner), and points redemptions all count
/// as "accounted for" - either way the unit has left inventory and is no
/// longer available/unsold, even though only customer_sale contributes
/// revenue.
int allocatedQuantity(int batchId, List<Sale> sales) {
  return sales
      .where(
        (s) =>
            s.batchId == batchId &&
            !s.isDeleted &&
            (s.saleType == SaleType.customerSale ||
                s.saleType == SaleType.internalConsumption ||
                s.saleType == SaleType.pointsRedemption),
      )
      .fold(0, (sum, s) => sum + s.quantity);
}

int remainingQuantity(Batch batch, List<Sale> sales) {
  return batch.countProduced - allocatedQuantity(batch.id, sales);
}

double batchRevenue(int batchId, List<Sale> sales) {
  return sumMoney(
    sales
        .where((s) => s.batchId == batchId && !s.isDeleted)
        .map((s) => s.amount),
  );
}

/// Full-price value of units taken for internal use. Quantity and the batch
/// unit price are authoritative so an old manually-entered amount cannot
/// understate the deduction from remittance.
double batchInternalConsumptionValue(Batch batch, List<Sale> sales) {
  final quantity = sales
      .where(
        (s) =>
            s.batchId == batch.id &&
            !s.isDeleted &&
            s.saleType == SaleType.internalConsumption,
      )
      .fold<int>(0, (sum, sale) => sum + sale.quantity);
  return fromCentavos(quantity * toCentavos(batch.unitPrice));
}

/// Discounts explicitly recorded on customer transactions. Entering a
/// discount is the manual approval step; only that recorded value reduces the
/// remittance.
double batchApprovedDiscountValue(Batch batch, List<Sale> sales) {
  return sumMoney(
    sales
        .where(
          (s) =>
              s.batchId == batch.id &&
              !s.isDeleted &&
              s.saleType == SaleType.customerSale,
        )
        .map((s) => s.discount > 0 ? s.discount : 0),
  );
}

/// Customer-approved add-ons are stored as a negative discount so older
/// clients and backups remain compatible with the existing sale schema.
double batchApprovedAddOnValue(Batch batch, List<Sale> sales) {
  return sumMoney(
    sales
        .where(
          (s) =>
              s.batchId == batch.id &&
              !s.isDeleted &&
              s.saleType == SaleType.customerSale,
        )
        .map((s) => s.discount < 0 ? -s.discount : 0),
  );
}

/// Full production value less units taken for internal use and manually
/// approved customer discounts.
double batchRemittanceValue(Batch batch, List<Sale> sales) {
  final value = subtractMoney(
    subtractMoney(
      batch.totalValue,
      batchInternalConsumptionValue(batch, sales),
    ),
    batchApprovedDiscountValue(batch, sales),
  );
  final adjusted = sumMoney([value, batchApprovedAddOnValue(batch, sales)]);
  return adjusted < 0 ? 0 : adjusted;
}

/// Actual customer charges recorded against the batch. Internal use and
/// loyalty redemptions are excluded from this reconciliation figure.
double batchRecordedCustomerTransactions(int batchId, List<Sale> sales) {
  return sumMoney(
    sales
        .where(
          (s) =>
              s.batchId == batchId &&
              !s.isDeleted &&
              s.saleType == SaleType.customerSale,
        )
        .map((s) => s.amount),
  );
}

/// Batches with remaining (unsold) stock first, then sold-out batches;
/// alphabetical by product name within each group.
List<Batch> sortBatchesUnsoldFirstThenAlpha(
  List<Batch> batches,
  List<Sale> sales,
  Product? Function(int productId) productById,
) {
  final sorted = [...batches];
  sorted.sort((a, b) {
    final aUnsold = remainingQuantity(a, sales) > 0;
    final bUnsold = remainingQuantity(b, sales) > 0;
    if (aUnsold != bUnsold) return aUnsold ? -1 : 1;
    final aTitle = productById(a.productId)?.title ?? '';
    final bTitle = productById(b.productId)?.title ?? '';
    return aTitle.toLowerCase().compareTo(bTitle.toLowerCase());
  });
  return sorted;
}
