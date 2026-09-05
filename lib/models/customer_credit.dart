/// A running credit ledger entry for a customer - e.g. they overpaid
/// because a batch's unit price was corrected downward after they'd
/// already paid at the old (higher) price. Positive [amount] = credit
/// owed to the customer; negative = credit consumed (applied to a later
/// purchase) or refunded in cash. A customer's balance is the sum of
/// their non-deleted entries. Not auto-applied to future sales - it's
/// surfaced in the UI so it can be deducted manually.
class CustomerCredit {
  final int id;
  final String? remoteId;
  final int customerId;
  final double amount;
  final String? reason;
  final int? saleId;
  final DateTime creditDate;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const CustomerCredit({
    required this.id,
    this.remoteId,
    required this.customerId,
    required this.amount,
    this.reason,
    this.saleId,
    required this.creditDate,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });
}
