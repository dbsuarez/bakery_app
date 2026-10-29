import '../models/batch.dart';
import '../models/cash_advance.dart';
import '../models/customer.dart';
import '../models/expense.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../utils/money.dart';
import 'batch_calculations.dart';
import 'customer_calculations.dart';

class CustomerStat {
  final Customer customer;
  final double value;
  const CustomerStat(this.customer, this.value);
}

class CustomerMonthWinner {
  final DateTime monthStart;
  final Customer customer;
  final double amount;
  const CustomerMonthWinner({
    required this.monthStart,
    required this.customer,
    required this.amount,
  });
}

class ProductStat {
  final Product product;
  final double value;
  const ProductStat(this.product, this.value);
}

class WeekRevenue {
  final DateTime weekStart;
  final double revenue;
  const WeekRevenue(this.weekStart, this.revenue);
}

class DayRevenue {
  final DateTime day;
  final double revenue;
  const DayRevenue(this.day, this.revenue);
}

class MonthRevenue {
  final DateTime monthStart;
  final double revenue;
  const MonthRevenue(this.monthStart, this.revenue);
}

class DashboardData {
  // Money cards
  final double outstandingReceivables;
  final double frontedAmount;
  final double unsoldValue;
  final double personalUnsoldValue;
  final double pendingRemittance;
  final double thisWeekRevenue;
  final double lastWeekRevenue;
  final double thisMonthRevenue;
  final double allTimeRevenue;
  final double? thisMonthEstimatedProfit;
  final double? allTimeEstimatedProfit;
  final double thisMonthExpenses;
  final double allTimeExpenses;
  // Gross profit (above) minus expenses - null exactly when the gross
  // figure it's built from is null (no batch cost data at all in the
  // period), same reasoning as thisMonthEstimatedProfit.
  final double? thisMonthNetProfit;
  final double? allTimeNetProfit;
  final double averageOrderValue;
  final double todayRevenue;
  final double bestPriorDayRevenue;
  final double bestPriorWeekRevenue;
  final int salesStreak;

  // Customer cards
  final List<CustomerStat> mostLoyal;
  final List<CustomerStat> topSpenders;
  final List<CustomerStat> topUnpaidBalances;
  final Customer? customerOfTheMonth;
  final Customer? customerOfAllTime;
  final List<CustomerMonthWinner> monthlyCustomerWinners;

  // Product cards
  final List<ProductStat> bestSellerByUnits;
  final List<ProductStat> bestSellerByRevenue;
  final List<ProductStat> bestProfitPerPiece;
  final List<ProductStat> unsoldWatchlist;
  final List<ProductStat> personalUnsoldWatchlist;

  // Operations
  final int batchCount;
  final List<Batch> batchesAwaitingRemittance;
  final List<Sale> recentPayments;
  final List<Batch> recentBatches;
  final List<Batch> activeBatches;
  final List<Batch> personalActiveBatches;

  // Personal - computed entirely from `Batch.isPersonal` batches, kept out
  // of every business figure above (spec: personal batches never go through
  // remittance and aren't part of the shop's business).
  final int personalBatchCount;
  final double personalTotalValueProduced;
  final double? personalTotalCost;
  final double? personalEstimatedProfit;
  final int personalUnitsConsumed;
  // A personal batch is never remitted, but a real (non-zero) customer_sale
  // can still be recorded against one - e.g. a few pieces actually sold off
  // a personal batch. Tracked separately since `businessSales` excludes
  // every sale tied to a personal batch, real money or not.
  final double personalOutstandingReceivables;
  final double personalRevenue;
  final double? personalThisMonthEstimatedProfit;

  // Trend
  final List<WeekRevenue> eightWeekTrend;
  final List<DayRevenue> dailyTrend;
  final List<MonthRevenue> monthlyTrend;

  // Personal trend - value of personal batches *produced* in each period
  // (by `Batch.batchDate`), not sales revenue, since personal batches
  // normally carry no real sale amount.
  final List<WeekRevenue> personalWeeklyTrend;
  final List<DayRevenue> personalDailyTrend;
  final List<MonthRevenue> personalMonthlyTrend;

  const DashboardData({
    required this.outstandingReceivables,
    required this.frontedAmount,
    required this.unsoldValue,
    required this.personalUnsoldValue,
    required this.pendingRemittance,
    required this.thisWeekRevenue,
    required this.lastWeekRevenue,
    required this.thisMonthRevenue,
    required this.allTimeRevenue,
    required this.thisMonthEstimatedProfit,
    required this.allTimeEstimatedProfit,
    required this.thisMonthExpenses,
    required this.allTimeExpenses,
    required this.thisMonthNetProfit,
    required this.allTimeNetProfit,
    required this.averageOrderValue,
    required this.todayRevenue,
    required this.bestPriorDayRevenue,
    required this.bestPriorWeekRevenue,
    required this.salesStreak,
    required this.mostLoyal,
    required this.topSpenders,
    required this.topUnpaidBalances,
    required this.customerOfTheMonth,
    required this.customerOfAllTime,
    required this.monthlyCustomerWinners,
    required this.bestSellerByUnits,
    required this.bestSellerByRevenue,
    required this.bestProfitPerPiece,
    required this.unsoldWatchlist,
    required this.personalUnsoldWatchlist,
    required this.batchCount,
    required this.batchesAwaitingRemittance,
    required this.recentPayments,
    required this.recentBatches,
    required this.activeBatches,
    required this.personalActiveBatches,
    required this.personalBatchCount,
    required this.personalTotalValueProduced,
    required this.personalTotalCost,
    required this.personalEstimatedProfit,
    required this.personalUnitsConsumed,
    required this.personalOutstandingReceivables,
    required this.personalRevenue,
    required this.personalThisMonthEstimatedProfit,
    required this.eightWeekTrend,
    required this.dailyTrend,
    required this.monthlyTrend,
    required this.personalWeeklyTrend,
    required this.personalDailyTrend,
    required this.personalMonthlyTrend,
  });
}

DateTime _startOfWeek(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  return date.subtract(Duration(days: date.weekday - 1));
}

DashboardData computeDashboard({
  required List<Product> products,
  required List<Customer> customers,
  required List<Batch> batches,
  required List<Sale> sales,
  List<SalePayment> salePayments = const [],
  List<CashAdvance> cashAdvances = const [],
  List<CashAdvancePayment> cashAdvancePayments = const [],
  List<Expense> expenses = const [],
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final liveBatches = batches.where((b) => !b.isDeleted).toList();
  final liveSales = sales.where((s) => !s.isDeleted).toList();
  final liveProducts = products.where((p) => !p.isDeleted).toList();
  final liveCustomers = normalCustomers(customers);

  // Personal batches (produced for the owner's own use, never remitted)
  // are kept out of every business-performance figure below - revenue,
  // profit, best-sellers, and customer stats all describe the shop's
  // business, not what the owner made for themselves.
  final personalBatchIds = liveBatches
      .where((b) => b.isPersonal)
      .map((b) => b.id)
      .toSet();
  final businessSales = liveSales
      .where((s) => !personalBatchIds.contains(s.batchId))
      .toList();

  final outstandingReceivables = sumMoney(
    businessSales
        .where((s) => !s.paid && s.saleType == SaleType.customerSale)
        .map((s) => saleRemainingAmount(s, salePayments)),
  );

  // Once a batch is remitted, its full value (paid + unpaid) has already
  // gone out; any still-unpaid amount is money the owner personally
  // fronted, not the shop till's receivable anymore.
  final remittedBatchIds = liveBatches
      .where((b) => b.remitted)
      .map((b) => b.id)
      .toSet();
  final frontedAmount = sumMoney(
    businessSales
        .where(
          (s) =>
              !s.paid &&
              s.saleType == SaleType.customerSale &&
              remittedBatchIds.contains(s.batchId),
        )
        .map((s) => saleRemainingAmount(s, salePayments)),
  );

  // Value of unsold inventory, tracked separately from receivables since
  // it isn't money any customer owes (spec section 7 rule 6). Computed from
  // remaining quantity on remitted or personal batches, not a placeholder
  // sale row - remaining stock on a still-active, non-personal batch might
  // yet sell. Kept as two separate totals (business vs. personal) since
  // personal batches were never headed for the shop till in the first place.
  double unsoldValueFor(bool personal) => sumMoney(
    liveBatches
        .where((b) => b.isPersonal == personal && (b.remitted || b.isPersonal))
        .map(
          (b) =>
              remainingQuantity(b, liveSales).clamp(0, 1 << 30) * b.unitPrice,
        ),
  );
  final unsoldValue = unsoldValueFor(false);
  final personalUnsoldValue = unsoldValueFor(true);

  final pendingRemittance = sumMoney(
    liveBatches
        .where((b) => !b.remitted && !b.isPersonal)
        .map((b) => batchRevenue(b.id, liveSales)),
  );

  final thisWeekStart = _startOfWeek(today);
  final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));

  double revenueInWeek(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return sumMoney(
      businessSales
          .where(
            (s) =>
                !s.saleDate.isBefore(weekStart) && s.saleDate.isBefore(weekEnd),
          )
          .map((s) => s.amount),
    );
  }

  final thisWeekRevenue = revenueInWeek(thisWeekStart);
  final lastWeekRevenue = revenueInWeek(lastWeekStart);

  // Personal-best detection (for "meaningful confetti", spec section 12)
  // and the sales streak - both look at per-day revenue/activity, so build
  // one day->revenue map and one day->has-a-sale set from businessSales.
  final todayKey = DateTime(today.year, today.month, today.day);
  final dailyRevenue = <DateTime, double>{};
  for (final s in businessSales) {
    final day = DateTime(s.saleDate.year, s.saleDate.month, s.saleDate.day);
    dailyRevenue[day] = fromCentavos(
      toCentavos(dailyRevenue[day] ?? 0) + toCentavos(s.amount),
    );
  }
  final todayRevenue = dailyRevenue[todayKey] ?? 0.0;
  final bestPriorDayRevenue = dailyRevenue.entries
      .where((e) => e.key.isBefore(todayKey))
      .fold(0.0, (m, e) => e.value > m ? e.value : m);

  final weeklyRevenue = <DateTime, double>{};
  for (final s in businessSales) {
    final weekStart = _startOfWeek(s.saleDate);
    weeklyRevenue[weekStart] = fromCentavos(
      toCentavos(weeklyRevenue[weekStart] ?? 0) + toCentavos(s.amount),
    );
  }
  final bestPriorWeekRevenue = weeklyRevenue.entries
      .where((e) => e.key.isBefore(thisWeekStart))
      .fold(0.0, (m, e) => e.value > m ? e.value : m);

  // Consecutive days with at least one sale, Duolingo-style: today doesn't
  // break the streak until the day is actually over - if nothing's been
  // sold yet today, count from yesterday instead of zeroing out at 12:01am.
  final saleDays = dailyRevenue.keys.toSet();
  var streakDay = todayKey;
  if (!saleDays.contains(streakDay)) {
    streakDay = streakDay.subtract(const Duration(days: 1));
  }
  // Sundays are exempt: a Sunday with no sale doesn't break the streak
  // (the bakery doesn't operate that day), it just doesn't add to the count.
  var salesStreak = 0;
  while (true) {
    if (saleDays.contains(streakDay)) {
      salesStreak++;
    } else if (streakDay.weekday != DateTime.sunday) {
      break;
    }
    streakDay = streakDay.subtract(const Duration(days: 1));
  }

  final monthStart = DateTime(today.year, today.month, 1);
  final monthBatches = liveBatches.where(
    (b) => !b.batchDate.isBefore(monthStart) && !b.isPersonal,
  );
  final hasCostData = monthBatches.any((b) => b.unitCost > 0);
  final thisMonthEstimatedProfit = hasCostData
      ? sumMoney(monthBatches.map((b) => b.estimatedProfit))
      : null;

  final thisMonthRevenue = sumMoney(
    businessSales
        .where((s) => !s.saleDate.isBefore(monthStart))
        .map((s) => s.amount),
  );

  final allTimeRevenue = sumMoney(businessSales.map((s) => s.amount));

  final businessBatches = liveBatches.where((b) => !b.isPersonal);
  final hasAnyCostData = businessBatches.any((b) => b.unitCost > 0);
  final allTimeEstimatedProfit = hasAnyCostData
      ? sumMoney(businessBatches.map((b) => b.estimatedProfit))
      : null;

  final liveExpenses = expenses.where((e) => !e.isDeleted);
  final thisMonthExpenses = sumMoney(
    liveExpenses
        .where((e) => !e.expenseDate.isBefore(monthStart))
        .map((e) => e.amount),
  );
  final allTimeExpenses = sumMoney(liveExpenses.map((e) => e.amount));
  final thisMonthNetProfit = thisMonthEstimatedProfit == null
      ? null
      : subtractMoney(thisMonthEstimatedProfit, thisMonthExpenses);
  final allTimeNetProfit = allTimeEstimatedProfit == null
      ? null
      : subtractMoney(allTimeEstimatedProfit, allTimeExpenses);

  final customerSales = businessSales.where(
    (s) => s.saleType == SaleType.customerSale,
  );
  final customerSaleCount = customerSales.length;
  final averageOrderValue = customerSaleCount == 0
      ? 0.0
      : fromCentavos(
          (customerSales
                      .map((s) => toCentavos(s.amount))
                      .fold<int>(0, (sum, amount) => sum + amount) /
                  customerSaleCount)
              .round(),
        );

  // Customer rankings must reconcile with the customer ledger. Unlike the
  // bakery profit/remittance figures, the ledger also includes real customer
  // sales made from personal batches.
  final customerLedgerSales = liveSales
      .where((s) => s.saleType == SaleType.customerSale)
      .toList();

  final loyalStats =
      liveCustomers
          .map(
            (c) => CustomerStat(
              c,
              customerOrderCount(c.id, customerLedgerSales).toDouble(),
            ),
          )
          .where((s) => s.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final spenderStats =
      liveCustomers
          .map(
            (c) =>
                CustomerStat(c, customerTotalSpent(c.id, customerLedgerSales)),
          )
          .where((s) => s.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final unpaidStats =
      liveCustomers
          .map(
            (c) => CustomerStat(
              c,
              customerBalance(
                c.id,
                customerLedgerSales,
                salePayments,
                cashAdvances,
                cashAdvancePayments,
              ),
            ),
          )
          .where((s) => s.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final customerOfAllTime = spenderStats.isNotEmpty
      ? spenderStats.first.customer
      : null;
  final customerById = {
    for (final customer in liveCustomers) customer.id: customer,
  };
  final monthlyCustomerCentavos = <int, Map<int, int>>{};
  for (final sale in customerLedgerSales) {
    final monthKey = sale.saleDate.year * 100 + sale.saleDate.month;
    final totals = monthlyCustomerCentavos.putIfAbsent(monthKey, () => {});
    totals.update(
      sale.customerId,
      (value) => value + toCentavos(sale.amount),
      ifAbsent: () => toCentavos(sale.amount),
    );
  }
  final monthlyCustomerWinners = <CustomerMonthWinner>[];
  for (final monthEntry in monthlyCustomerCentavos.entries) {
    final eligible =
        monthEntry.value.entries
            .where((entry) => customerById.containsKey(entry.key))
            .toList()
          ..sort((a, b) {
            final amountCompare = b.value.compareTo(a.value);
            if (amountCompare != 0) return amountCompare;
            return customerById[a.key]!.name.toLowerCase().compareTo(
              customerById[b.key]!.name.toLowerCase(),
            );
          });
    if (eligible.isEmpty) continue;
    final winner = eligible.first;
    monthlyCustomerWinners.add(
      CustomerMonthWinner(
        monthStart: DateTime(monthEntry.key ~/ 100, monthEntry.key % 100),
        customer: customerById[winner.key]!,
        amount: fromCentavos(winner.value),
      ),
    );
  }
  monthlyCustomerWinners.sort((a, b) => b.monthStart.compareTo(a.monthStart));
  Customer? customerOfTheMonth;
  for (final winner in monthlyCustomerWinners) {
    if (winner.monthStart.year == today.year &&
        winner.monthStart.month == today.month) {
      customerOfTheMonth = winner.customer;
      break;
    }
  }

  double unitsForProduct(int productId) {
    final batchIds = liveBatches
        .where((b) => b.productId == productId && !b.isPersonal)
        .map((b) => b.id);
    return businessSales
        .where(
          (s) =>
              batchIds.contains(s.batchId) &&
              s.saleType == SaleType.customerSale,
        )
        .fold(0.0, (sum, s) => sum + s.quantity);
  }

  double revenueForProduct(int productId) {
    final batchIds = liveBatches
        .where((b) => b.productId == productId && !b.isPersonal)
        .map((b) => b.id);
    return sumMoney(
      businessSales
          .where((s) => batchIds.contains(s.batchId))
          .map((s) => s.amount),
    );
  }

  // Unsold inventory is "final" once a batch is remitted (the baking cycle
  // is closed) or is personal (it never goes through remittance at all);
  // an active, non-personal batch's remaining stock might still sell. Split
  // by personal vs. business so the watchlist doesn't mix the two.
  int unsoldForProduct(int productId, {required bool personal}) {
    final productBatches = liveBatches
        .where(
          (b) =>
              b.productId == productId &&
              b.isPersonal == personal &&
              (b.remitted || b.isPersonal),
        )
        .toList();
    return productBatches.fold<int>(
      0,
      (sum, b) => sum + remainingQuantity(b, liveSales).clamp(0, 1 << 30),
    );
  }

  final bestSellerByUnits =
      liveProducts
          .map((p) => ProductStat(p, unitsForProduct(p.id)))
          .where((s) => s.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final bestSellerByRevenue =
      liveProducts
          .map((p) => ProductStat(p, revenueForProduct(p.id)))
          .where((s) => s.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  // Average (unit_price - unit_cost) across a product's batches that have
  // cost data - personal batches excluded, same as every other business
  // figure. A product with no cost data on any batch is left out entirely
  // rather than shown as zero margin.
  double? profitPerPieceForProduct(int productId) {
    final costBatches = liveBatches
        .where(
          (b) => b.productId == productId && !b.isPersonal && b.unitCost > 0,
        )
        .toList();
    if (costBatches.isEmpty) return null;
    final totalMargin = costBatches.fold<int>(
      0,
      (sum, b) => sum + toCentavos(b.unitPrice) - toCentavos(b.unitCost),
    );
    return fromCentavos((totalMargin / costBatches.length).round());
  }

  final bestProfitPerPiece =
      liveProducts
          .map((p) {
            final margin = profitPerPieceForProduct(p.id);
            return margin == null ? null : ProductStat(p, margin);
          })
          .whereType<ProductStat>()
          .where((s) => s.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final unsoldWatchlist =
      liveProducts
          .map(
            (p) => ProductStat(
              p,
              unsoldForProduct(p.id, personal: false).toDouble(),
            ),
          )
          .where((s) => s.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final personalUnsoldWatchlist =
      liveProducts
          .map(
            (p) => ProductStat(
              p,
              unsoldForProduct(p.id, personal: true).toDouble(),
            ),
          )
          .where((s) => s.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

  final batchCount = liveBatches.length;

  final batchesAwaitingRemittance =
      liveBatches.where((b) => !b.remitted && !b.isPersonal).toList()
        ..sort((a, b) => a.batchDate.compareTo(b.batchDate));

  final recentPayments =
      liveSales.where((s) => s.paid && s.datePaid != null).toList()
        ..sort((a, b) => b.datePaid!.compareTo(a.datePaid!));

  final recentBatches = [...liveBatches]
    ..sort((a, b) => b.batchDate.compareTo(a.batchDate));

  final activeBatches = liveBatches
      .where(
        (b) =>
            !b.remitted && !b.isPersonal && remainingQuantity(b, liveSales) > 0,
      )
      .toList();

  final personalActiveBatches = liveBatches
      .where((b) => b.isPersonal && remainingQuantity(b, liveSales) > 0)
      .toList();

  final personalBatches = liveBatches.where((b) => b.isPersonal).toList();
  final personalBatchCount = personalBatches.length;
  final personalTotalValueProduced = sumMoney(
    personalBatches.map((b) => b.totalValue),
  );
  final personalHasCostData = personalBatches.any((b) => b.unitCost > 0);
  final personalTotalCost = personalHasCostData
      ? sumMoney(personalBatches.map((b) => b.countProduced * b.unitCost))
      : null;
  final personalEstimatedProfit = personalTotalCost == null
      ? null
      : subtractMoney(personalTotalValueProduced, personalTotalCost);
  final personalBatchIdSet = personalBatches.map((b) => b.id).toSet();
  final personalUnitsConsumed = liveSales
      .where((s) => personalBatchIdSet.contains(s.batchId))
      .fold<int>(0, (sum, s) => sum + s.quantity);
  final personalOutstandingReceivables = sumMoney(
    liveSales
        .where(
          (s) =>
              personalBatchIdSet.contains(s.batchId) &&
              !s.paid &&
              s.saleType == SaleType.customerSale,
        )
        .map((s) => saleRemainingAmount(s, salePayments)),
  );
  final personalRevenue = sumMoney(
    liveSales
        .where(
          (s) =>
              personalBatchIdSet.contains(s.batchId) &&
              s.saleType == SaleType.customerSale,
        )
        .map((s) => s.amount),
  );
  final personalMonthBatches = personalBatches.where(
    (b) => !b.batchDate.isBefore(monthStart),
  );
  final personalHasMonthCostData = personalMonthBatches.any(
    (b) => b.unitCost > 0,
  );
  final personalThisMonthEstimatedProfit = personalHasMonthCostData
      ? sumMoney(personalMonthBatches.map((b) => b.estimatedProfit))
      : null;

  final eightWeekTrend = List.generate(8, (i) {
    final weekStart = thisWeekStart.subtract(Duration(days: 7 * (7 - i)));
    return WeekRevenue(weekStart, revenueInWeek(weekStart));
  });

  final dailyTrend = List.generate(14, (i) {
    final day = todayKey.subtract(Duration(days: 13 - i));
    return DayRevenue(day, dailyRevenue[day] ?? 0.0);
  });

  double revenueInMonth(DateTime monthStart) {
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
    return sumMoney(
      businessSales
          .where(
            (s) =>
                !s.saleDate.isBefore(monthStart) &&
                s.saleDate.isBefore(monthEnd),
          )
          .map((s) => s.amount),
    );
  }

  final monthlyTrend = List.generate(6, (i) {
    final offset = 5 - i;
    final monthStart2 = DateTime(today.year, today.month - offset, 1);
    return MonthRevenue(monthStart2, revenueInMonth(monthStart2));
  });

  // Personal trend uses batch production date/value, not sales revenue -
  // personal batches normally carry no real sale amount to trend on.
  double personalValueOnDay(DateTime day) => sumMoney(
    personalBatches
        .where(
          (b) =>
              b.batchDate.year == day.year &&
              b.batchDate.month == day.month &&
              b.batchDate.day == day.day,
        )
        .map((b) => b.totalValue),
  );

  double personalValueInWeek(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 7));
    return sumMoney(
      personalBatches
          .where(
            (b) =>
                !b.batchDate.isBefore(weekStart) &&
                b.batchDate.isBefore(weekEnd),
          )
          .map((b) => b.totalValue),
    );
  }

  double personalValueInMonth(DateTime monthStart) {
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
    return sumMoney(
      personalBatches
          .where(
            (b) =>
                !b.batchDate.isBefore(monthStart) &&
                b.batchDate.isBefore(monthEnd),
          )
          .map((b) => b.totalValue),
    );
  }

  final personalDailyTrend = List.generate(14, (i) {
    final day = todayKey.subtract(Duration(days: 13 - i));
    return DayRevenue(day, personalValueOnDay(day));
  });

  final personalWeeklyTrend = List.generate(8, (i) {
    final weekStart = thisWeekStart.subtract(Duration(days: 7 * (7 - i)));
    return WeekRevenue(weekStart, personalValueInWeek(weekStart));
  });

  final personalMonthlyTrend = List.generate(6, (i) {
    final offset = 5 - i;
    final monthStart2 = DateTime(today.year, today.month - offset, 1);
    return MonthRevenue(monthStart2, personalValueInMonth(monthStart2));
  });

  return DashboardData(
    outstandingReceivables: outstandingReceivables,
    frontedAmount: frontedAmount,
    unsoldValue: unsoldValue,
    personalUnsoldValue: personalUnsoldValue,
    pendingRemittance: pendingRemittance,
    thisWeekRevenue: thisWeekRevenue,
    lastWeekRevenue: lastWeekRevenue,
    thisMonthRevenue: thisMonthRevenue,
    allTimeRevenue: allTimeRevenue,
    thisMonthEstimatedProfit: thisMonthEstimatedProfit,
    allTimeEstimatedProfit: allTimeEstimatedProfit,
    thisMonthExpenses: thisMonthExpenses,
    allTimeExpenses: allTimeExpenses,
    thisMonthNetProfit: thisMonthNetProfit,
    allTimeNetProfit: allTimeNetProfit,
    averageOrderValue: averageOrderValue,
    todayRevenue: todayRevenue,
    bestPriorDayRevenue: bestPriorDayRevenue,
    bestPriorWeekRevenue: bestPriorWeekRevenue,
    salesStreak: salesStreak,
    mostLoyal: loyalStats.take(5).toList(),
    topSpenders: spenderStats.take(5).toList(),
    topUnpaidBalances: unpaidStats.take(5).toList(),
    customerOfTheMonth: customerOfTheMonth,
    customerOfAllTime: customerOfAllTime,
    monthlyCustomerWinners: monthlyCustomerWinners,
    bestSellerByUnits: bestSellerByUnits.take(5).toList(),
    bestSellerByRevenue: bestSellerByRevenue.take(5).toList(),
    bestProfitPerPiece: bestProfitPerPiece.take(5).toList(),
    unsoldWatchlist: unsoldWatchlist.take(5).toList(),
    personalUnsoldWatchlist: personalUnsoldWatchlist.take(5).toList(),
    batchCount: batchCount,
    batchesAwaitingRemittance: batchesAwaitingRemittance,
    recentPayments: recentPayments.take(10).toList(),
    recentBatches: recentBatches.take(10).toList(),
    activeBatches: activeBatches,
    personalActiveBatches: personalActiveBatches,
    personalBatchCount: personalBatchCount,
    personalTotalValueProduced: personalTotalValueProduced,
    personalTotalCost: personalTotalCost,
    personalEstimatedProfit: personalEstimatedProfit,
    personalUnitsConsumed: personalUnitsConsumed,
    personalOutstandingReceivables: personalOutstandingReceivables,
    personalRevenue: personalRevenue,
    personalThisMonthEstimatedProfit: personalThisMonthEstimatedProfit,
    eightWeekTrend: eightWeekTrend,
    dailyTrend: dailyTrend,
    monthlyTrend: monthlyTrend,
    personalWeeklyTrend: personalWeeklyTrend,
    personalDailyTrend: personalDailyTrend,
    personalMonthlyTrend: personalMonthlyTrend,
  );
}
