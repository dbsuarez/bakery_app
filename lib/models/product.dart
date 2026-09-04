/// Which loyalty-points pool a product's sales belong to (spec: points earned
/// buying one category must not fund redemptions in the other).
enum ProductCategory {
  bakery('bakery'),
  merchandise('merchandise');

  final String value;
  const ProductCategory(this.value);

  static ProductCategory fromValue(String value) {
    return ProductCategory.values.firstWhere(
      (c) => c.value == value,
      orElse: () => ProductCategory.bakery,
    );
  }
}

class Product {
  final int id;
  final String? remoteId;
  final String title;
  final String? imageUrl;
  final ProductCategory category;
  final bool isArchived;
  final DateTime updatedAt;
  final bool isDirty;
  final bool isDeleted;

  const Product({
    required this.id,
    this.remoteId,
    required this.title,
    this.imageUrl,
    this.category = ProductCategory.bakery,
    this.isArchived = false,
    required this.updatedAt,
    this.isDirty = true,
    this.isDeleted = false,
  });
}
