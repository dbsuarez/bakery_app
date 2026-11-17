enum ReservationStatus {
  pending('pending'),
  contacted('contacted'),
  fulfilled('fulfilled'),
  cancelled('cancelled');

  final String value;
  const ReservationStatus(this.value);

  static ReservationStatus fromValue(String value) =>
      ReservationStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => ReservationStatus.pending,
      );
}

/// A lead left by a visitor on the public announce/reserve page
/// (web/products.html) against one product - not the same as
/// [Sale.isReservation], which is a committed sale against a known
/// customer/batch. This is just a heads-up for the owner to follow up on and
/// convert into a real sale manually; it never touches batches or sales.
class ProductReservation {
  final int id;
  final String? remoteId;
  final int? productId;
  final String productTitle;

  /// Set when this reservation was made through the customer's own SOA
  /// link (web/soa.html) rather than typed anonymously on the public
  /// products page - lets this be matched back to a real customer record.
  final int? customerId;
  final String customerName;
  final String customerContact;
  final int quantity;
  final String? note;
  final ReservationStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  const ProductReservation({
    required this.id,
    this.remoteId,
    this.productId,
    required this.productTitle,
    this.customerId,
    required this.customerName,
    required this.customerContact,
    this.quantity = 1,
    this.note,
    this.status = ReservationStatus.pending,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });
}
