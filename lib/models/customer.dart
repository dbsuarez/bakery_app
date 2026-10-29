class Customer {
  final int id;
  final String? remoteId;
  final String name;
  final String? phone;
  final bool isArchived;

  /// Free-text group/location label (e.g. "Office", "Central") - the set of
  /// valid names is configured in Settings, not enforced here. Null means
  /// ungrouped.
  final String? group;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const Customer({
    required this.id,
    this.remoteId,
    required this.name,
    this.phone,
    this.isArchived = false,
    this.group,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });

  /// "Unsold" is a bookkeeping placeholder from the legacy spreadsheet
  /// (unsold inventory recorded as a fake receivable), not a real customer,
  /// so it's excluded from normal customer analytics (spec section 7, rule
  /// 16). "Dante" is a real customer, despite the spec's original assumption.
  bool get isPseudoCustomer => name == 'Unsold';
}
