import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Business-wide settings shown on customer-facing documents and used for
/// loyalty point math: the business name, and the points program's earn
/// rate. Stored in the Supabase auth user's metadata rather than a
/// dedicated table - tied to the account, not the device, so it's the same
/// on web and phone without a schema migration.
class BusinessSettingsController extends ChangeNotifier {
  static const _kNameKey = 'business_name';
  static const _kPesosPerPointKey = 'pesos_per_point';
  static const _kSameDayBonusKey = 'same_day_bonus_percent';
  static const _kRedeemPesosPerPointKey = 'redeem_pesos_per_point';
  static const _kSameDayBonusStartDateKey = 'same_day_bonus_start_date';
  static const _kCustomerGroupsKey = 'customer_groups';
  static const _kPaymentMethodsKey = 'payment_methods';

  static const defaultName = 'My Bakery';
  static const defaultPaymentMethods = ['Cash', 'AUB', 'Maribank', 'GCash'];
  static const defaultPesosPerPoint = 10.0; // ₱10 spent = 1 point earned
  static const defaultSameDayBonusPercent = 50.0;
  static const defaultRedeemPesosPerPoint = 1.0; // 1 point = ₱1 when redeeming
  // Payment dates on sales before this weren't tracked precisely (backfilled
  // with a default), so the same-day bonus is withheld for them regardless
  // of what date_paid says.
  static final defaultSameDayBonusStartDate = DateTime(2026, 8, 11);

  String _name = defaultName;
  double _pesosPerPoint = defaultPesosPerPoint;
  double _sameDayBonusPercent = defaultSameDayBonusPercent;
  double _redeemPesosPerPoint = defaultRedeemPesosPerPoint;
  DateTime _sameDayBonusStartDate = defaultSameDayBonusStartDate;
  List<String> _customerGroups = [];
  List<String> _paymentMethods = List.of(defaultPaymentMethods);

  String get name => _name;
  double get pesosPerPoint => _pesosPerPoint;
  double get sameDayBonusPercent => _sameDayBonusPercent;
  double get redeemPesosPerPoint => _redeemPesosPerPoint;
  DateTime get sameDayBonusStartDate => _sameDayBonusStartDate;
  List<String> get customerGroups => List.unmodifiable(_customerGroups);
  List<String> get paymentMethods => List.unmodifiable(_paymentMethods);

  StreamSubscription<AuthState>? _authSub;

  BusinessSettingsController() {
    // The provider is created at app boot, before sign-in completes, so the
    // initial load() below usually finds no user yet - reload whenever the
    // auth state changes (sign-in, session restore, metadata update).
    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((_) => load());
  }

  /// Re-fetches the user from Supabase (not the locally cached session) so
  /// a value set on another device shows up here too - `currentUser` alone
  /// is a local cache that only updates on this device's own auth events.
  Future<void> load() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    try {
      final response = await Supabase.instance.client.auth.getUser();
      final meta = response.user?.userMetadata;
      final nameVal = meta?[_kNameKey];
      final pppVal = meta?[_kPesosPerPointKey];
      final bonusVal = meta?[_kSameDayBonusKey];
      final redeemPppVal = meta?[_kRedeemPesosPerPointKey];
      final bonusStartVal = meta?[_kSameDayBonusStartDateKey];
      final customerGroupsVal = meta?[_kCustomerGroupsKey];
      final paymentMethodsVal = meta?[_kPaymentMethodsKey];
      final resolvedName =
          (nameVal is String && nameVal.trim().isNotEmpty) ? nameVal : defaultName;
      final resolvedPpp =
          (pppVal is num && pppVal > 0) ? pppVal.toDouble() : defaultPesosPerPoint;
      final resolvedBonus = (bonusVal is num && bonusVal >= 0)
          ? bonusVal.toDouble()
          : defaultSameDayBonusPercent;
      final resolvedRedeemPpp = (redeemPppVal is num && redeemPppVal > 0)
          ? redeemPppVal.toDouble()
          : defaultRedeemPesosPerPoint;
      final resolvedBonusStart = (bonusStartVal is String)
          ? (DateTime.tryParse(bonusStartVal) ?? defaultSameDayBonusStartDate)
          : defaultSameDayBonusStartDate;
      final resolvedCustomerGroups = customerGroupsVal is List
          ? customerGroupsVal.whereType<String>().toList()
          : <String>[];
      final resolvedPaymentMethods = paymentMethodsVal is List
          ? paymentMethodsVal.whereType<String>().toList()
          : List.of(defaultPaymentMethods);
      if (resolvedName != _name ||
          resolvedPpp != _pesosPerPoint ||
          resolvedBonus != _sameDayBonusPercent ||
          resolvedRedeemPpp != _redeemPesosPerPoint ||
          resolvedBonusStart != _sameDayBonusStartDate ||
          !listEquals(resolvedCustomerGroups, _customerGroups) ||
          !listEquals(resolvedPaymentMethods, _paymentMethods)) {
        _name = resolvedName;
        _pesosPerPoint = resolvedPpp;
        _sameDayBonusPercent = resolvedBonus;
        _redeemPesosPerPoint = resolvedRedeemPpp;
        _sameDayBonusStartDate = resolvedBonusStart;
        _customerGroups = resolvedCustomerGroups;
        _paymentMethods = resolvedPaymentMethods;
        notifyListeners();
      }
    } catch (_) {
      // Not signed in yet, or a transient network error - keep current value.
    }
  }

  Future<void> setName(String name) async {
    final trimmed = name.trim();
    _name = trimmed.isEmpty ? defaultName : trimmed;
    notifyListeners();
    await _saveMetadata();
  }

  Future<void> setPesosPerPoint(double value) async {
    _pesosPerPoint = value > 0 ? value : defaultPesosPerPoint;
    notifyListeners();
    await _saveMetadata();
  }

  Future<void> setSameDayBonusPercent(double value) async {
    _sameDayBonusPercent = value >= 0 ? value : defaultSameDayBonusPercent;
    notifyListeners();
    await _saveMetadata();
  }

  Future<void> setRedeemPesosPerPoint(double value) async {
    _redeemPesosPerPoint = value > 0 ? value : defaultRedeemPesosPerPoint;
    notifyListeners();
    await _saveMetadata();
  }

  Future<void> setSameDayBonusStartDate(DateTime value) async {
    _sameDayBonusStartDate = DateTime(value.year, value.month, value.day);
    notifyListeners();
    await _saveMetadata();
  }

  Future<void> setCustomerGroups(List<String> groups) async {
    _customerGroups = groups
        .map((g) => g.trim())
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList();
    notifyListeners();
    await _saveMetadata();
  }

  Future<void> setPaymentMethods(List<String> methods) async {
    final cleaned = methods
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toSet()
        .toList();
    _paymentMethods = cleaned.isEmpty ? List.of(defaultPaymentMethods) : cleaned;
    notifyListeners();
    await _saveMetadata();
  }

  // Sends the full local state every time, not just the changed field - in
  // case the server merges shallowly or replaces user_metadata wholesale,
  // this keeps all keys consistent either way.
  Future<void> _saveMetadata() async {
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(data: {
        _kNameKey: _name,
        _kPesosPerPointKey: _pesosPerPoint,
        _kSameDayBonusKey: _sameDayBonusPercent,
        _kRedeemPesosPerPointKey: _redeemPesosPerPoint,
        _kSameDayBonusStartDateKey: _sameDayBonusStartDate.toIso8601String(),
        _kCustomerGroupsKey: _customerGroups,
        _kPaymentMethodsKey: _paymentMethods,
      }),
    );
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
