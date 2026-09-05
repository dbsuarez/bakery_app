import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../analytics/batch_calculations.dart';
import '../../analytics/dashboard_analytics.dart';
import '../../app_state.dart';
import '../../build_info.dart';
import '../../celebration/celebration_controller.dart';
import '../../models/batch.dart';
import '../../theme/theme_controller.dart';
import '../../utils/app_date_format.dart';
import '../../utils/segment_label.dart';
import '../batch_add_transactions/batch_add_transactions_screen.dart';
import '../batches/batch_detail_screen.dart';
import '../batches/batch_form_screen.dart';
import '../batches/batches_list_screen.dart';
import '../customers/customer_ledger_screen.dart';
import '../remittance/remittance_screen.dart';
import '../single_sale/single_sale_screen.dart';
import '../widgets/product_avatar.dart';
import 'personal_activity_screen.dart';

final _currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);

/// Single-letter weekday abbreviation, except Thursday ("Th") and Sunday
/// ("Su") - both would otherwise collide with Tuesday ("T") and Saturday
/// ("S") respectively.
String _dayLetter(DateTime day) {
  const letters = ['M', 'T', 'W', 'Th', 'F', 'S', 'Su'];
  return letters[day.weekday - 1];
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _kCelebratedDayKey = 'celebrated_best_day_revenue';
  static const _kCelebratedWeekKey = 'celebrated_best_week_revenue';
  _MoneyFilter _moneyFilter = _MoneyFilter.baking;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final data = computeDashboard(
      products: appState.products,
      customers: appState.customers,
      batches: appState.batches,
      sales: appState.sales,
      salePayments: appState.salePayments,
    );

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkPersonalBest(data));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text('Dashboard'),
            const Spacer(),
            Text(
              'build: $buildTime',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _QuickActions(),
          _FavoritesInStock(appState: appState),
          const SizedBox(height: 16),
          _SectionTitle('Money'),
          _MoneyCards(
            data: data,
            filter: _moneyFilter,
            onFilterChanged: (f) => setState(() => _moneyFilter = f),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Revenue trend'),
          _TrendChart(data: data, moneyFilter: _moneyFilter),
          const SizedBox(height: 16),
          _ResponsiveSections(data: data),
          if (data.personalUnsoldValue > 0 ||
              data.personalActiveBatches.isNotEmpty ||
              data.personalUnsoldWatchlist.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            _PersonalGroup(data: data),
          ],
        ],
      ),
    );
  }

  // Meaningful confetti (spec section 12): a new personal-best revenue day
  // or week. Persisted via SharedPreferences so it only fires once per new
  // record, not on every 10-second dashboard refresh.
  Future<void> _checkPersonalBest(DashboardData data) async {
    final prefs = await SharedPreferences.getInstance();
    final celebratedDay =
        prefs.getDouble(_kCelebratedDayKey) ?? data.bestPriorDayRevenue;
    final celebratedWeek =
        prefs.getDouble(_kCelebratedWeekKey) ?? data.bestPriorWeekRevenue;

    var shouldCelebrate = false;
    if (data.todayRevenue > 0 &&
        data.todayRevenue > data.bestPriorDayRevenue &&
        data.todayRevenue > celebratedDay) {
      await prefs.setDouble(_kCelebratedDayKey, data.todayRevenue);
      shouldCelebrate = true;
    }
    if (data.thisWeekRevenue > 0 &&
        data.thisWeekRevenue > data.bestPriorWeekRevenue &&
        data.thisWeekRevenue > celebratedWeek) {
      await prefs.setDouble(_kCelebratedWeekKey, data.thisWeekRevenue);
      shouldCelebrate = true;
    }
    if (shouldCelebrate && mounted) {
      context.read<CelebrationController>().celebrate();
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// Lays the Customers/Products/Operations sections out in multiple columns
/// on wide screens (tablet/desktop) instead of one long vertical stack.
class _ResponsiveSections extends StatelessWidget {
  final DashboardData data;
  const _ResponsiveSections({required this.data});

  @override
  Widget build(BuildContext context) {
    final sections = [
      _Section('Customers', _CustomerCards(data: data)),
      _Section('Products', _ProductCards(data: data)),
      _Section('Operations', _OperationsCards(data: data)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100 ? 3 : (width >= 700 ? 2 : 1);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in sections) ...[
                _SectionTitle(section.title),
                section.child,
                const SizedBox(height: 16),
              ],
            ],
          );
        }
        const spacing = 16.0;
        final columnWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 16,
          children: [
            for (final section in sections)
              SizedBox(
                width: columnWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(section.title),
                    section.child,
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Section {
  final String title;
  final Widget child;
  const _Section(this.title, this.child);
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BatchFormScreen()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add Batch'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const BatchAddTransactionsScreen(),
            ),
          ),
          icon: const Icon(Icons.groups),
          label: const Text('Batch Add Transactions'),
        ),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SingleSaleScreen()),
          ),
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Log Single Transaction'),
        ),
      ],
    );
  }
}

class _FavoritesInStock extends StatelessWidget {
  final AppState appState;
  const _FavoritesInStock({required this.appState});

  @override
  Widget build(BuildContext context) {
    final entries = <({String productTitle, List<String> customerNames})>[];
    for (final batch in appState.batches) {
      if (batch.isDeleted) continue;
      if (remainingQuantity(batch, appState.sales) <= 0) continue;
      final fans = appState.customersFavoriting(batch.productId);
      if (fans.isEmpty) continue;
      final product = appState.productById(batch.productId);
      entries.add((
        productTitle: product?.title ?? '?',
        customerNames: fans.map((c) => c.name).toList(),
      ));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        color: Colors.amber.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.favorite, color: Colors.red.shade400, size: 20),
                  const SizedBox(width: 8),
                  Text('Favorites in stock',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              for (final e in entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${e.productTitle} - ${e.customerNames.join(', ')}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? description;
  final VoidCallback? onTap;
  const _StatTile({
    required this.label,
    required this.value,
    this.description,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showDescription =
        context.watch<ThemeController>().showCardDescriptions;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                value,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (description != null && showDescription) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _MoneyFilter { baking, personal, all }

class _MoneyCards extends StatelessWidget {
  final DashboardData data;
  final _MoneyFilter filter;
  final ValueChanged<_MoneyFilter> onFilterChanged;
  const _MoneyCards({
    required this.data,
    required this.filter,
    required this.onFilterChanged,
  });

  List<Widget> _bakingTiles(BuildContext context) {
    final trend = data.thisWeekRevenue - data.lastWeekRevenue;
    void goToBatches(BatchFilter filter) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BatchesListScreen(initialFilter: filter),
          ),
        );

    return <Widget>[
      _StatTile(
        label: 'Outstanding receivables',
        value: _currency.format(data.outstandingReceivables),
        description: 'Unpaid customer sales, still on active batches',
      ),
      if (data.frontedAmount > 0)
        _StatTile(
          label: 'Fronted (remitted, uncollected)',
          value: _currency.format(data.frontedAmount),
          description: 'Unpaid sales on batches already remitted - money you fronted',
        ),
      if (data.unsoldValue > 0)
        _StatTile(
          label: 'Unsold value',
          value: _currency.format(data.unsoldValue),
          description: 'Remaining stock on remitted batches, at unit price',
          onTap: () => goToBatches(BatchFilter.remitted),
        ),
      _StatTile(
        label: 'Pending remittance',
        value: _currency.format(data.pendingRemittance),
        description: 'Revenue from batches not yet remitted',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RemittanceScreen()),
        ),
      ),
      _StatTile(
        label: 'This week revenue',
        value: _currency.format(data.thisWeekRevenue),
        description: 'Business sales, Monday to today',
      ),
      _StatTile(
        label:
            'Last week (${trend >= 0 ? '+' : ''}${_currency.format(trend)})',
        value: _currency.format(data.lastWeekRevenue),
        description: 'Prior full week, vs. this week',
      ),
      _StatTile(
        label: 'This month revenue',
        value: _currency.format(data.thisMonthRevenue),
        description: 'Business sales, 1st of month to today',
      ),
      _StatTile(
        label: 'Est. profit (this month)',
        value: data.thisMonthEstimatedProfit == null
            ? '-'
            : _currency.format(data.thisMonthEstimatedProfit),
        description: data.thisMonthEstimatedProfit == null
            ? 'Set a unit cost on a batch to see this'
            : 'Revenue minus cost, batches produced this month',
      ),
      _StatTile(
        label: 'All-time revenue',
        value: _currency.format(data.allTimeRevenue),
        description: 'All business sales ever recorded',
      ),
      _StatTile(
        label: 'Est. profit (all time)',
        value: data.allTimeEstimatedProfit == null
            ? '-'
            : _currency.format(data.allTimeEstimatedProfit),
        description: data.allTimeEstimatedProfit == null
            ? 'Set a unit cost on a batch to see this'
            : 'Revenue minus cost, across every batch',
      ),
      if (data.averageOrderValue > 0)
        _StatTile(
          label: 'Average order value',
          value: _currency.format(data.averageOrderValue),
          description: 'Average amount per customer sale',
        ),
      if (data.salesStreak > 0)
        _StatTile(
          label: 'Sales streak',
          value: '🔥 ${data.salesStreak}-day',
          description: 'Consecutive days with at least one sale',
        ),
    ];
  }

  List<Widget> _personalTiles(BuildContext context) {
    return <Widget>[
      _StatTile(
        label: 'Personal batches (all time)',
        value: '${data.personalBatchCount}',
        description: 'Batches made for your own use',
      ),
      if (data.personalOutstandingReceivables > 0)
        _StatTile(
          label: 'Personal outstanding receivables',
          value: _currency.format(data.personalOutstandingReceivables),
          description: 'Unpaid real sales off a personal batch',
        ),
      _StatTile(
        label: 'Personal unsold value',
        value: _currency.format(data.personalUnsoldValue),
        description: 'Remaining personal stock, at unit price',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                const BatchesListScreen(initialFilter: BatchFilter.personal),
          ),
        ),
      ),
      _StatTile(
        label: 'Personal value produced (all time)',
        value: _currency.format(data.personalTotalValueProduced),
        description: 'Notional value of everything made for yourself',
      ),
      if (data.personalRevenue > 0)
        _StatTile(
          label: 'Personal revenue (all time)',
          value: _currency.format(data.personalRevenue),
          description: 'Real money from actual sales off a personal batch',
        ),
      _StatTile(
        label: 'Personal cost (all time)',
        value: data.personalTotalCost == null
            ? '-'
            : _currency.format(data.personalTotalCost),
        description: data.personalTotalCost == null
            ? 'Set a unit cost on a personal batch to see this'
            : 'Cost of everything made for yourself',
      ),
      _StatTile(
        label: 'Personal est. profit (this month)',
        value: data.personalThisMonthEstimatedProfit == null
            ? '-'
            : _currency.format(data.personalThisMonthEstimatedProfit),
        description: data.personalThisMonthEstimatedProfit == null
            ? 'Set a unit cost on a personal batch to see this'
            : 'Value produced minus cost, this month',
      ),
      _StatTile(
        label: 'Personal est. profit (all time)',
        value: data.personalEstimatedProfit == null
            ? '-'
            : _currency.format(data.personalEstimatedProfit),
        description: data.personalEstimatedProfit == null
            ? 'Set a unit cost on a personal batch to see this'
            : 'Value produced minus cost',
      ),
      _StatTile(
        label: 'Personal units used',
        value: '${data.personalUnitsConsumed}',
        description: 'Units consumed or given away from personal batches',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PersonalActivityScreen(),
          ),
        ),
      ),
    ];
  }

  static double? _sumNullable(double? a, double? b) =>
      a == null && b == null ? null : (a ?? 0) + (b ?? 0);

  List<Widget> _allTiles(BuildContext context) {
    void goToBatches(BatchFilter filter) => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BatchesListScreen(initialFilter: filter),
          ),
        );
    final unsoldValue = data.unsoldValue + data.personalUnsoldValue;
    final allTimeRevenue = data.allTimeRevenue + data.personalRevenue;
    final thisMonthProfit = _sumNullable(
        data.thisMonthEstimatedProfit, data.personalThisMonthEstimatedProfit);
    final allTimeProfit =
        _sumNullable(data.allTimeEstimatedProfit, data.personalEstimatedProfit);
    final receivables =
        data.outstandingReceivables + data.personalOutstandingReceivables;
    // Personal batches rarely carry real sale revenue, so - same as the
    // trend chart's "All" - these use personal value *produced* in the
    // period as the personal contribution, not personal sale revenue.
    final personalWeekly = data.personalWeeklyTrend;
    final thisWeekAll =
        data.thisWeekRevenue + personalWeekly.last.revenue;
    final lastWeekAll = data.lastWeekRevenue +
        personalWeekly[personalWeekly.length - 2].revenue;
    final trend = thisWeekAll - lastWeekAll;
    final thisMonthAll =
        data.thisMonthRevenue + data.personalMonthlyTrend.last.revenue;

    return <Widget>[
      _StatTile(
        label: 'Outstanding receivables',
        value: _currency.format(receivables),
        description: 'Unpaid customer sales, business + personal',
      ),
      if (data.frontedAmount > 0)
        _StatTile(
          label: 'Fronted (remitted, uncollected)',
          value: _currency.format(data.frontedAmount),
          description: 'Unpaid sales on batches already remitted - money you fronted',
        ),
      if (unsoldValue > 0)
        _StatTile(
          label: 'Unsold value',
          value: _currency.format(unsoldValue),
          description: 'Remaining stock, business + personal, at unit price',
          onTap: () => goToBatches(BatchFilter.all),
        ),
      _StatTile(
        label: 'Pending remittance',
        value: _currency.format(data.pendingRemittance),
        description: 'Revenue from batches not yet remitted',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RemittanceScreen()),
        ),
      ),
      _StatTile(
        label: 'This week revenue',
        value: _currency.format(thisWeekAll),
        description: 'Business sales + personal value produced, Monday to today',
      ),
      _StatTile(
        label:
            'Last week (${trend >= 0 ? '+' : ''}${_currency.format(trend)})',
        value: _currency.format(lastWeekAll),
        description: 'Prior full week, vs. this week',
      ),
      _StatTile(
        label: 'This month revenue',
        value: _currency.format(thisMonthAll),
        description: 'Business sales + personal value produced, 1st of month to today',
      ),
      _StatTile(
        label: 'Est. profit (this month)',
        value: thisMonthProfit == null ? '-' : _currency.format(thisMonthProfit),
        description: thisMonthProfit == null
            ? 'Set a unit cost on a batch to see this'
            : 'Revenue minus cost, business + personal, this month',
      ),
      _StatTile(
        label: 'All-time revenue',
        value: _currency.format(allTimeRevenue),
        description: 'All real sales ever recorded, business + personal',
      ),
      _StatTile(
        label: 'Est. profit (all time)',
        value: allTimeProfit == null ? '-' : _currency.format(allTimeProfit),
        description: allTimeProfit == null
            ? 'Set a unit cost on a batch to see this'
            : 'Revenue minus cost, business + personal',
      ),
      if (data.averageOrderValue > 0)
        _StatTile(
          label: 'Average order value',
          value: _currency.format(data.averageOrderValue),
          description: 'Average amount per customer sale',
        ),
      if (data.salesStreak > 0)
        _StatTile(
          label: 'Sales streak',
          value: '🔥 ${data.salesStreak}-day',
          description: 'Consecutive days with at least one sale',
        ),
      _StatTile(
        label: 'Personal batches (all time)',
        value: '${data.personalBatchCount}',
        description: 'Batches made for your own use',
      ),
      _StatTile(
        label: 'Personal value produced (all time)',
        value: _currency.format(data.personalTotalValueProduced),
        description: 'Notional value of everything made for yourself',
      ),
      if (data.personalTotalCost != null)
        _StatTile(
          label: 'Personal cost (all time)',
          value: _currency.format(data.personalTotalCost),
          description: 'Cost of everything made for yourself',
        ),
      _StatTile(
        label: 'Personal units used',
        value: '${data.personalUnitsConsumed}',
        description: 'Units consumed or given away from personal batches',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PersonalActivityScreen()),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tiles = switch (filter) {
      _MoneyFilter.baking => _bakingTiles(context),
      _MoneyFilter.personal => _personalTiles(context),
      _MoneyFilter.all => _allTiles(context),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<_MoneyFilter>(
          segments: [
            ButtonSegment(
              value: _MoneyFilter.all,
              icon: const Icon(Icons.apps),
              label: compactLabel('All'),
              tooltip: 'All',
            ),
            ButtonSegment(
              value: _MoneyFilter.baking,
              icon: const Icon(Icons.bakery_dining_outlined),
              label: compactLabel('Baking'),
              tooltip: 'Baking',
            ),
            ButtonSegment(
              value: _MoneyFilter.personal,
              icon: const Icon(Icons.person_outline),
              label: compactLabel('Personal'),
              tooltip: 'Personal',
            ),
          ],
          selected: {filter},
          onSelectionChanged: (s) => onFilterChanged(s.first),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 900 ? 4 : (width >= 320 ? 2 : 1);
            const spacing = 8.0;
            final tileWidth = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final tile in tiles)
                  SizedBox(width: tileWidth, child: tile),
              ],
            );
          },
        ),
      ],
    );
  }
}

enum _TrendPeriod { daily, weekly, monthly }

class _TrendChart extends StatefulWidget {
  final DashboardData data;
  final _MoneyFilter moneyFilter;
  const _TrendChart({required this.data, required this.moneyFilter});

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  _TrendPeriod _period = _TrendPeriod.weekly;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final includeBaking = widget.moneyFilter != _MoneyFilter.personal;
    final includePersonal = widget.moneyFilter != _MoneyFilter.baking;

    final List<double> values;
    final List<String> labels;
    switch (_period) {
      case _TrendPeriod.daily:
        values = [
          for (var i = 0; i < data.dailyTrend.length; i++)
            (includeBaking ? data.dailyTrend[i].revenue : 0) +
                (includePersonal ? data.personalDailyTrend[i].revenue : 0)
        ];
        labels = [for (final d in data.dailyTrend) _dayLetter(d.day)];
        break;
      case _TrendPeriod.weekly:
        values = [
          for (var i = 0; i < data.eightWeekTrend.length; i++)
            (includeBaking ? data.eightWeekTrend[i].revenue : 0) +
                (includePersonal ? data.personalWeeklyTrend[i].revenue : 0)
        ];
        labels = [
          for (final w in data.eightWeekTrend)
            DateFormat('M/d').format(w.weekStart)
        ];
        break;
      case _TrendPeriod.monthly:
        values = [
          for (var i = 0; i < data.monthlyTrend.length; i++)
            (includeBaking ? data.monthlyTrend[i].revenue : 0) +
                (includePersonal ? data.personalMonthlyTrend[i].revenue : 0)
        ];
        labels = [
          for (final m in data.monthlyTrend)
            DateFormat('MMM').format(m.monthStart)
        ];
        break;
    }
    final maxY = values.fold<double>(1, (m, v) => v > m ? v : m);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                switch (widget.moneyFilter) {
                  _MoneyFilter.baking => 'Showing: Baking',
                  _MoneyFilter.personal => 'Showing: Personal',
                  _MoneyFilter.all => 'Showing: All',
                },
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const SizedBox(height: 4),
            SegmentedButton<_TrendPeriod>(
              segments: [
                ButtonSegment(
                  value: _TrendPeriod.daily,
                  icon: const Icon(Icons.calendar_view_day),
                  label: compactLabel('Daily'),
                  tooltip: 'Daily',
                ),
                ButtonSegment(
                  value: _TrendPeriod.weekly,
                  icon: const Icon(Icons.calendar_view_week),
                  label: compactLabel('Weekly'),
                  tooltip: 'Weekly',
                ),
                ButtonSegment(
                  value: _TrendPeriod.monthly,
                  icon: const Icon(Icons.calendar_view_month),
                  label: compactLabel('Monthly'),
                  tooltip: 'Monthly',
                ),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              width: double.infinity,
              child: BarChart(
                BarChartData(
                  maxY: maxY * 1.2,
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= labels.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              labels[i],
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  barGroups: [
                    for (var i = 0; i < values.length; i++)
                      BarChartGroupData(x: i, barRods: [
                        BarChartRodData(
                          toY: values[i],
                          color: Theme.of(context).colorScheme.primary,
                          width: _period == _TrendPeriod.daily ? 10 : 16,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerCards extends StatelessWidget {
  final DashboardData data;
  const _CustomerCards({required this.data});

  void _openLedger(BuildContext context, int customerId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerLedgerScreen(customerId: customerId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.customerOfTheMonth != null)
          ListTile(
            leading: const Icon(Icons.emoji_events),
            title: const Text('Customer of the Month'),
            subtitle: Text(data.customerOfTheMonth!.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openLedger(context, data.customerOfTheMonth!.id),
          ),
        _NamedList(
          'Most loyal',
          [
            for (final s in data.mostLoyal)
              _Entry('${s.customer.name} (${s.value.toInt()} orders)',
                  onTap: () => _openLedger(context, s.customer.id)),
          ],
        ),
        _NamedList(
          'Top spenders',
          [
            for (final s in data.topSpenders)
              _Entry('${s.customer.name} (${_currency.format(s.value)})',
                  onTap: () => _openLedger(context, s.customer.id)),
          ],
        ),
        _NamedList(
          'Top unpaid balances',
          [
            for (final s in data.topUnpaidBalances)
              _Entry('${s.customer.name} (${_currency.format(s.value)})',
                  onTap: () => _openLedger(context, s.customer.id)),
          ],
        ),
        _NamedList(
          'At-risk (30+ days)',
          [
            for (final c in data.atRisk)
              _Entry(c.name, onTap: () => _openLedger(context, c.id)),
          ],
        ),
      ],
    );
  }
}

class _ProductCards extends StatelessWidget {
  final DashboardData data;
  const _ProductCards({required this.data});

  void _openBatchesForProduct(BuildContext context, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BatchesListScreen(initialSearch: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NamedList(
          'Best-seller by units',
          [
            for (final s in data.bestSellerByUnits)
              _Entry('${s.product.title} (${s.value.toInt()} units)',
                  imageUrl: s.product.imageUrl,
                  onTap: () => _openBatchesForProduct(context, s.product.title)),
          ],
        ),
        _NamedList(
          'Best-seller by revenue',
          [
            for (final s in data.bestSellerByRevenue)
              _Entry('${s.product.title} (${_currency.format(s.value)})',
                  imageUrl: s.product.imageUrl,
                  onTap: () => _openBatchesForProduct(context, s.product.title)),
          ],
        ),
        _NamedList(
          'Unsold / overproduction watchlist',
          [
            for (final s in data.unsoldWatchlist)
              _Entry('${s.product.title} (${s.value.toInt()} unsold)',
                  imageUrl: s.product.imageUrl,
                  onTap: () => _openBatchesForProduct(context, s.product.title)),
          ],
        ),
      ],
    );
  }
}

class _OperationsCards extends StatelessWidget {
  final DashboardData data;
  const _OperationsCards({required this.data});

  void _openBatch(BuildContext context, int batchId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BatchDetailScreen(batchId: batchId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String label(Batch b) {
      final title = appState.productById(b.productId)?.title ?? 'Unknown product';
      return '$title - ${appDateFormat.format(b.batchDate)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NamedList(
          'Batches awaiting remittance',
          [
            for (final b in data.batchesAwaitingRemittance)
              _Entry(label(b),
                  imageUrl: appState.productById(b.productId)?.imageUrl,
                  onTap: () => _openBatch(context, b.id)),
          ],
        ),
        _NamedList(
          'Active batches with remaining quantity',
          [
            for (final b in data.activeBatches)
              _Entry(label(b),
                  imageUrl: appState.productById(b.productId)?.imageUrl,
                  onTap: () => _openBatch(context, b.id)),
          ],
        ),
      ],
    );
  }
}

/// Personal batches (spec: `Batch.isPersonal`) are kept out of every business
/// figure elsewhere on the dashboard, so this group is visually set apart
/// (own tinted container, own heading) rather than sitting as just another
/// column next to Customers/Products/Operations.
class _PersonalGroup extends StatelessWidget {
  final DashboardData data;
  const _PersonalGroup({required this.data});

  void _openBatch(BuildContext context, int batchId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BatchDetailScreen(batchId: batchId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    String label(Batch b) {
      final title = appState.productById(b.productId)?.title ?? 'Unknown product';
      return '$title - ${appDateFormat.format(b.batchDate)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, size: 18, color: Theme.of(context).colorScheme.onSecondaryContainer),
              const SizedBox(width: 8),
              Text('Personal', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2, bottom: 12),
            child: Text(
              "For your own use - see the Money section's Personal/All filter for figures",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _NamedList(
            'Personal batches with remaining stock',
            [
              for (final b in data.personalActiveBatches)
                _Entry(label(b),
                    imageUrl: appState.productById(b.productId)?.imageUrl,
                    onTap: () => _openBatch(context, b.id)),
            ],
          ),
          _NamedList(
            'Personal unsold watchlist',
            [
              for (final s in data.personalUnsoldWatchlist)
                _Entry(
                  '${s.product.title} (${s.value.toInt()} unsold)',
                  imageUrl: s.product.imageUrl,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BatchesListScreen(initialSearch: s.product.title),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Entry {
  final String label;
  final VoidCallback? onTap;
  final String? imageUrl;
  const _Entry(this.label, {this.onTap, this.imageUrl});
}

class _NamedList extends StatelessWidget {
  final String title;
  final List<_Entry> items;
  const _NamedList(this.title, this.items);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final item in items)
              InkWell(
                onTap: item.onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      if (item.imageUrl != null) ...[
                        ProductAvatar(imageUrl: item.imageUrl, radius: 10),
                        const SizedBox(width: 8),
                      ] else
                        const Text('• '),
                      Expanded(child: Text(item.label)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
