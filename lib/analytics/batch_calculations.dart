import '../models/batch.dart';
import '../models/product.dart';
import '../models/sale.dart';

/// Spec section 7 rule 7: batch remaining quantity = produced quantity -
/// allocated quantity. Real customer sales, internal consumption
/// (freebies/samples eaten by the owner), and points redemptions all count
/// as "accounted for" - either way the unit has left inventory and is no
/// longer available/unsold, even though only customer_sale contributes
/// revenue.
int allocatedQuantity(int batchId, List<Sale> sales) {
  return sales
      .where((s) =>
          s.batchId == batchId &&
          !s.isDeleted &&
          (s.saleType == SaleType.customerSale ||
              s.saleType == SaleType.internalConsumption ||
              s.saleType == SaleType.pointsRedemption))
      .fold(0, (sum, s) => sum + s.quantity);
}

int remainingQuantity(Batch batch, List<Sale> sales) {
  return batch.countProduced - allocatedQuantity(batch.id, sales);
}

double batchRevenue(int batchId, List<Sale> sales) {
  return sales
      .where((s) => s.batchId == batchId && !s.isDeleted)
      .fold(0.0, (sum, s) => sum + s.amount);
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
