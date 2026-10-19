/// Marks a customer's favorite-in-stock heads-up "handled" for one
/// specific batch, without un-favoriting the product - the same favorite
/// resurfaces on the Dashboard for the *next* batch of that product. A
/// pure on/off marker, hard-deleted like [CustomerFavorite].
class FavoriteDismissal {
  final int customerId;
  final int batchId;
  const FavoriteDismissal({required this.customerId, required this.batchId});
}
