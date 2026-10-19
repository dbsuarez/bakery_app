/// A standalone business expense (rent, utilities, packaging, ...) not
/// tied to a batch's own unit cost - feeds into the Dashboard's net
/// profit figure alongside batch cost-of-goods.
class Expense {
  final int id;
  final String? remoteId;
  final double amount;
  final String category;
  final DateTime expenseDate;
  final String? notes;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const Expense({
    required this.id,
    this.remoteId,
    required this.amount,
    this.category = 'Other',
    required this.expenseDate,
    this.notes,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });
}
