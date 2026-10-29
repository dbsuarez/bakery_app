class CashAdvance {
  final int id;
  final String? remoteId;
  final int customerId;
  final DateTime advanceDate;
  final double amount;
  final bool paid;
  final DateTime? datePaid;
  final String? paymentMethod;
  final String? notes;
  final DateTime updatedAt;
  final bool isDeleted;

  const CashAdvance({
    required this.id,
    this.remoteId,
    required this.customerId,
    required this.advanceDate,
    required this.amount,
    this.paid = false,
    this.datePaid,
    this.paymentMethod,
    this.notes,
    required this.updatedAt,
    this.isDeleted = false,
  });
}

class CashAdvancePayment {
  final int id;
  final String? remoteId;
  final int cashAdvanceId;
  final double amount;
  final DateTime paymentDate;
  final String? paymentMethod;
  final String? notes;
  final DateTime updatedAt;
  final bool isDeleted;

  const CashAdvancePayment({
    required this.id,
    this.remoteId,
    required this.cashAdvanceId,
    required this.amount,
    required this.paymentDate,
    this.paymentMethod,
    this.notes,
    required this.updatedAt,
    this.isDeleted = false,
  });
}
