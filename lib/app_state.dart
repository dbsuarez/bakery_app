import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models/batch.dart';
import 'models/customer.dart';
import 'models/customer_favorite.dart';
import 'models/loyalty_adjustment.dart';
import 'models/product.dart';
import 'models/sale.dart';
import 'repository/bakery_repository.dart';

/// Combines the repository's watch streams into synchronously-readable
/// lists for the UI, via a single ChangeNotifier.
class AppState extends ChangeNotifier {
  final BakeryRepository repository;

  List<Product> products = [];
  List<Customer> customers = [];
  List<Batch> batches = [];
  List<Sale> sales = [];
  List<LoyaltyAdjustment> loyaltyAdjustments = [];
  List<CustomerFavorite> customerFavorites = [];

  late final StreamSubscription _productsSub;
  late final StreamSubscription _customersSub;
  late final StreamSubscription _batchesSub;
  late final StreamSubscription _salesSub;
  late final StreamSubscription _loyaltyAdjustmentsSub;
  late final StreamSubscription _customerFavoritesSub;

  AppState(this.repository) {
    _productsSub = repository.watchProducts().listen((v) {
      products = v;
      notifyListeners();
    });
    _customersSub = repository.watchCustomers().listen((v) {
      customers = v;
      notifyListeners();
    });
    _batchesSub = repository.watchBatches().listen((v) {
      batches = v;
      notifyListeners();
    });
    _salesSub = repository.watchSales().listen((v) {
      sales = v;
      notifyListeners();
    });
    _loyaltyAdjustmentsSub = repository.watchLoyaltyAdjustments().listen((v) {
      loyaltyAdjustments = v;
      notifyListeners();
    });
    _customerFavoritesSub = repository.watchCustomerFavorites().listen((v) {
      customerFavorites = v;
      notifyListeners();
    });
  }

  /// Customers (excluding archived/pseudo) who have favorited [productId].
  List<Customer> customersFavoriting(int productId) {
    final customerIds = customerFavorites
        .where((f) => f.productId == productId)
        .map((f) => f.customerId)
        .toSet();
    return customers
        .where((c) =>
            customerIds.contains(c.id) && !c.isArchived && !c.isPseudoCustomer)
        .toList();
  }

  Product? productById(int id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  Customer? customerById(int id) {
    for (final c in customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  Batch? batchById(int id) {
    for (final b in batches) {
      if (b.id == id) return b;
    }
    return null;
  }

  @override
  void dispose() {
    _productsSub.cancel();
    _customersSub.cancel();
    _batchesSub.cancel();
    _salesSub.cancel();
    _loyaltyAdjustmentsSub.cancel();
    _customerFavoritesSub.cancel();
    super.dispose();
  }
}
