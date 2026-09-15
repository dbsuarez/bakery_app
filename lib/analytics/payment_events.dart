import '../models/sale.dart';

/// One actual payment received - either a full settlement (a sale marked
/// paid in one go) or a single installment toward a partial payment. This
/// is the unit "payments by method" and the payment log report over, since
/// a sale itself only carries its *most recent* payment method, not the
/// full history of how it was paid off in installments.
class PaymentEvent {
  final int saleId;
  final int customerId;
  final int batchId;
  final int quantity;
  final double amount;
  final String? paymentMethod;
  final DateTime date;

  /// The note on this specific payment (an installment's own note), or -
  /// for a sale paid off in one go, with no installment row of its own -
  /// the underlying sale's note, since that's the closest thing to a note
  /// on "how this payment happened".
  final String? notes;

  const PaymentEvent({
    required this.saleId,
    required this.customerId,
    required this.batchId,
    required this.quantity,
    required this.amount,
    required this.paymentMethod,
    required this.date,
    required this.notes,
  });
}

/// Every payment actually received against a `customer_sale` row: each
/// installment in [payments] counts as its own event, and a sale paid in
/// full in one go (no installment rows at all) counts as one event for its
/// full amount - never both, so a fully-paid sale isn't double-counted.
List<PaymentEvent> allPaymentEvents(
  List<Sale> sales,
  List<SalePayment> payments,
) {
  final salesById = {for (final s in sales) s.id: s};
  final events = <PaymentEvent>[];

  final installmentSaleIds = <int>{};
  for (final p in payments) {
    if (p.isDeleted) continue;
    final sale = salesById[p.saleId];
    if (sale == null || sale.saleType != SaleType.customerSale) continue;
    installmentSaleIds.add(p.saleId);
    events.add(
      PaymentEvent(
        saleId: sale.id,
        customerId: sale.customerId,
        batchId: sale.batchId,
        quantity: sale.quantity,
        amount: p.amount,
        paymentMethod: p.paymentMethod,
        date: p.paymentDate,
        notes: p.notes,
      ),
    );
  }

  for (final s in sales) {
    if (s.isDeleted ||
        !s.paid ||
        s.datePaid == null ||
        s.saleType != SaleType.customerSale) {
      continue;
    }
    if (installmentSaleIds.contains(s.id)) continue;
    events.add(
      PaymentEvent(
        saleId: s.id,
        customerId: s.customerId,
        batchId: s.batchId,
        quantity: s.quantity,
        amount: s.amount,
        paymentMethod: s.paymentMethod,
        date: s.datePaid!,
        notes: s.notes,
      ),
    );
  }

  return events;
}
