import '../models/batch.dart';
import '../models/customer.dart';
import '../models/customer_credit.dart';
import '../models/customer_favorite.dart';
import '../models/expense.dart';
import '../models/favorite_dismissal.dart';
import '../models/loyalty_adjustment.dart';
import '../models/product.dart';
import '../models/sale.dart';

abstract class BakeryRepository {
  /// Requests an immediate refresh of all watched data.
  void refresh();

  Stream<List<Product>> watchProducts();
  Stream<List<Customer>> watchCustomers();
  Stream<List<Batch>> watchBatches();
  Stream<List<Sale>> watchSales();
  Stream<List<LoyaltyAdjustment>> watchLoyaltyAdjustments();
  Stream<List<CustomerFavorite>> watchCustomerFavorites();
  Stream<List<SalePayment>> watchSalePayments();
  Stream<List<CustomerCredit>> watchCustomerCredits();
  Stream<List<FavoriteDismissal>> watchFavoriteDismissals();
  Stream<List<Expense>> watchExpenses();

  Future<void> createProduct(Product product);
  Future<void> createCustomer(Customer customer);
  Future<void> createBatch(Batch batch);
  Future<void> addSingleSale(Sale sale);
  Future<void> addBatchTransactions(
    int batchId,
    List<BatchTransactionEntry> entries, {
    bool allowOverallocate = false,
  });
  Future<void> markSalePaid(
    int saleId,
    DateTime paymentDate, {
    String? paymentMethod,
  });
  Future<void> markSaleUnpaid(int saleId);
  Future<void> markBatchRemitted(int batchId, DateTime dateRemitted);
  Future<void> unlockBatch(int batchId);

  /// Re-locks a batch that was previously unlocked, without touching
  /// `remitted`/`date_remitted` - the counterpart to [unlockBatch].
  Future<void> lockBatch(int batchId);

  // Additions beyond the spec's core interface, needed for edit/detail
  // screens (spec section 11 lists Batches/Customers/Products edit flows).
  Future<void> updateProduct(Product product);
  Future<void> updateCustomer(Customer customer);
  Future<void> updateBatch(Batch batch);
  Future<void> updateSale(Sale sale, {bool allowOverallocate = false});
  Future<void> revertBatchRemittance(int batchId);

  /// Soft-deletes a transaction entirely - not the same as editing it to
  /// zero: this fully undoes it, freeing its quantity back to the batch's
  /// available stock (`remainingQuantity` already excludes deleted sales).
  Future<void> deleteSale(int saleId);

  /// Records a manual loyalty-points correction (goodwill credit, error
  /// fix) - not tied to a real purchase, so it can't be a `Sale` row.
  Future<void> addLoyaltyAdjustment(LoyaltyAdjustment adjustment);

  /// Moves every sale and loyalty adjustment from [fromCustomerId] onto
  /// [intoCustomerId], then soft-deletes [fromCustomerId] - for merging an
  /// accidental duplicate customer record into the real one. Irreversible
  /// from the app (the merged-away customer is soft-deleted, not restored).
  Future<void> mergeCustomers(int fromCustomerId, int intoCustomerId);

  Future<void> addCustomerFavorite(int customerId, int productId);
  Future<void> removeCustomerFavorite(int customerId, int productId);

  /// Records a partial/installment payment against [saleId]. If it (plus
  /// any prior payments) now covers the sale's full amount, the sale is
  /// automatically flipped to paid with this payment's date.
  Future<void> addSalePayment(SalePayment payment);

  /// Records a customer credit ledger entry - positive to grant credit
  /// (e.g. an overpayment), negative to consume it (applied to a purchase
  /// or refunded in cash).
  Future<void> addCustomerCredit(CustomerCredit credit);

  /// Re-prices every non-deleted `customer_sale` transaction in [batchId]
  /// to [newUnitPrice] (preserving each sale's discount). Unpaid sales just
  /// have their amount updated. Paid sales also get their amount updated,
  /// but the difference from what was actually collected at [oldUnitPrice]
  /// is recorded as a [CustomerCredit] entry against that sale's customer,
  /// rather than silently disappearing - a decrease becomes credit owed to
  /// them, an increase becomes a (rare) negative credit.
  Future<void> reconcileBatchUnitPrice(
    int batchId,
    double oldUnitPrice,
    double newUnitPrice,
  );

  /// Marks a customer's favorite-in-stock heads-up handled for [batchId]
  /// specifically - it'll surface again for the next batch of that product.
  Future<void> dismissFavorite(int customerId, int batchId);

  Future<void> addExpense(Expense expense);
  Future<void> updateExpense(Expense expense);

  /// Soft-deletes an expense.
  Future<void> deleteExpense(int expenseId);
}
