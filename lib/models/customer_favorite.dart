/// A product a customer likes - used to prompt a heads-up when a new batch
/// of that product is baked. Pure on/off preference, no history to keep.
class CustomerFavorite {
  final int customerId;
  final int productId;
  const CustomerFavorite({required this.customerId, required this.productId});
}
