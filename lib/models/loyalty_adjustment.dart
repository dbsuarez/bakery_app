import 'product.dart';

/// A manual loyalty-points correction not tied to a real purchase - a
/// goodwill credit, or fixing a mistake - since a `Sale` row requires a
/// batch and can't represent an arbitrary points delta.
class LoyaltyAdjustment {
  final int id;
  final String? remoteId;
  final int customerId;
  final ProductCategory category;
  final int points;
  final String? reason;
  final DateTime adjustmentDate;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const LoyaltyAdjustment({
    required this.id,
    this.remoteId,
    required this.customerId,
    required this.category,
    required this.points,
    this.reason,
    required this.adjustmentDate,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });
}
