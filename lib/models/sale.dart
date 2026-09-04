enum SaleType {
  customerSale('customer_sale'),
  unsold('unsold'),
  internalConsumption('internal_consumption'),
  pointsRedemption('points_redemption');

  final String value;
  const SaleType(this.value);

  static SaleType fromValue(String value) {
    return SaleType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => SaleType.customerSale,
    );
  }
}

class Sale {
  final int id;
  final String? remoteId;
  final int? legacyId;
  final int batchId;
  final int customerId;
  final DateTime saleDate;
  final int quantity;
  final double amount;
  final bool paid;
  final DateTime? datePaid;
  final SaleType saleType;
  final String? notes;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const Sale({
    required this.id,
    this.remoteId,
    this.legacyId,
    required this.batchId,
    required this.customerId,
    required this.saleDate,
    this.quantity = 1,
    required this.amount,
    this.paid = false,
    this.datePaid,
    this.saleType = SaleType.customerSale,
    this.notes,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });
}

class BatchTransactionEntry {
  final int customerId;
  final int quantity;
  final double amount;
  final bool paid;
  final DateTime? datePaid;
  final String? notes;

  const BatchTransactionEntry({
    required this.customerId,
    required this.quantity,
    required this.amount,
    required this.paid,
    this.datePaid,
    this.notes,
  });
}
