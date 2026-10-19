import 'dart:async';

import 'package:flutter/widgets.dart';

import 'models/batch.dart';
import 'models/customer.dart';
import 'models/customer_credit.dart';
import 'models/customer_favorite.dart';
import 'models/expense.dart';
import 'models/favorite_dismissal.dart';
import 'models/loyalty_adjustment.dart';
import 'models/product.dart';
import 'models/sale.dart';
import 'repository/bakery_repository.dart';

/// Combines the repository's watch streams into synchronously-readable
/// lists for the UI, via a single ChangeNotifier.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final BakeryRepository repository;

  List<Product> products = [];
  List<Customer> customers = [];
  List<Batch> batches = [];
  List<Sale> sales = [];
  List<LoyaltyAdjustment> loyaltyAdjustments = [];
  List<CustomerFavorite> customerFavorites = [];
  List<SalePayment> salePayments = [];
  List<CustomerCredit> customerCredits = [];
  List<FavoriteDismissal> favoriteDismissals = [];
  List<Expense> expenses = [];

  late final StreamSubscription _productsSub;
  late final StreamSubscription _customersSub;
  late final StreamSubscription _batchesSub;
  late final StreamSubscription _salesSub;
  late final StreamSubscription _loyaltyAdjustmentsSub;
  late final StreamSubscription _customerFavoritesSub;
  late final StreamSubscription _salePaymentsSub;
  late final StreamSubscription _customerCreditsSub;
  late final StreamSubscription _favoriteDismissalsSub;
  late final StreamSubscription _expensesSub;

  AppState(this.repository) {
    WidgetsBinding.instance.addObserver(this);
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
    _salePaymentsSub = repository.watchSalePayments().listen((v) {
      salePayments = v;
      notifyListeners();
    });
    _customerCreditsSub = repository.watchCustomerCredits().listen((v) {
      customerCredits = v;
      notifyListeners();
    });
    _favoriteDismissalsSub = repository.watchFavoriteDismissals().listen((v) {
      favoriteDismissals = v;
      notifyListeners();
    });
    _expensesSub = repository.watchExpenses().listen((v) {
      expenses = v;
      notifyListeners();
    });
  }

  /// Refresh when returning to the foreground so decisions are not based on
  /// data that may have changed while the app was inactive.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) repository.refresh();
  }

  void refresh() => repository.refresh();

  /// Customers (excluding archived/pseudo) who have favorited [productId].
  List<Customer> customersFavoriting(int productId) {
    final customerIds = customerFavorites
        .where((f) => f.productId == productId)
        .map((f) => f.customerId)
        .toSet();
    return customers
        .where(
          (c) =>
              customerIds.contains(c.id) &&
              !c.isArchived &&
              !c.isPseudoCustomer,
        )
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
    WidgetsBinding.instance.removeObserver(this);
    _productsSub.cancel();
    _customersSub.cancel();
    _batchesSub.cancel();
    _salesSub.cancel();
    _loyaltyAdjustmentsSub.cancel();
    _customerFavoritesSub.cancel();
    _salePaymentsSub.cancel();
    _customerCreditsSub.cancel();
    _favoriteDismissalsSub.cancel();
    _expensesSub.cancel();
    super.dispose();
  }
}
