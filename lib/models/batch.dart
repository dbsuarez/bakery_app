class Batch {
  final int id;
  final String? remoteId;
  final int? legacyId;
  final int productId;
  final DateTime batchDate;
  final int countProduced;
  final double unitPrice;
  final double unitCost;
  final double totalValue;
  final bool remitted;
  final DateTime? dateRemitted;
  final bool locked;
  final bool isPersonal;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const Batch({
    required this.id,
    this.remoteId,
    this.legacyId,
    required this.productId,
    required this.batchDate,
    required this.countProduced,
    required this.unitPrice,
    this.unitCost = 0,
    required this.totalValue,
    this.remitted = false,
    this.dateRemitted,
    this.locked = false,
    this.isPersonal = false,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });

  /// Spec section 7 rule 13: total_value - (count_produced * unit_cost).
  double get estimatedProfit => totalValue - (countProduced * unitCost);
}
