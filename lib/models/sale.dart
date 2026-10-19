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

  /// Purely informational: how much was knocked off full price to arrive
  /// at [amount]. [amount] is still the actual charged/owed figure
  /// everywhere else in the app.
  final double discount;
  final bool paid;
  final DateTime? datePaid;
  final String? paymentMethod;
  final SaleType saleType;
  final String? notes;

  /// A reservation: the customer has committed to buying from this batch
  /// before it's actually ready/in stock, as opposed to a normal sale
  /// logged once it's available. Still counts toward allocated quantity -
  /// this is a display/organizational flag, not a different business rule.
  final bool isReservation;
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
    this.discount = 0,
    this.paid = false,
    this.datePaid,
    this.paymentMethod,
    this.saleType = SaleType.customerSale,
    this.notes,
    this.isReservation = false,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });
}

/// An installment/partial payment recorded against an unpaid [Sale]. The
/// sale keeps its full amount and only flips to `paid` once the sum of its
/// payments covers it - see [Sale.discount] comment for the parallel
/// "informational, doesn't change the source of truth" pattern.
class SalePayment {
  final int id;
  final String? remoteId;
  final int saleId;
  final double amount;
  final DateTime paymentDate;
  final String? paymentMethod;
  final String? notes;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const SalePayment({
    required this.id,
    this.remoteId,
    required this.saleId,
    required this.amount,
    required this.paymentDate,
    this.paymentMethod,
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
  final double discount;
  final bool paid;
  final DateTime? datePaid;
  final String? paymentMethod;
  final String? notes;
  final bool isReservation;

  const BatchTransactionEntry({
    required this.customerId,
    required this.quantity,
    required this.amount,
    this.discount = 0,
    required this.paid,
    this.datePaid,
    this.paymentMethod,
    this.notes,
    this.isReservation = false,
  });
}
