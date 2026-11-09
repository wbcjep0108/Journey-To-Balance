import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/financial_entry.dart';
import '../providers/budget_provider.dart';
import '../providers/currency_provider.dart';
import '../screens/home/daily_spending_page.dart';
import '../services/firestore_finance_service.dart';

/// Combines a fetched base snapshot with the provider's live entries for the
/// week [weekStart] (inclusive) to [weekEnd] (exclusive).
///
/// Rules, applied per category:
/// - Live entries inside the week are always used, and the live copy wins when
///   an id also exists in [base].
/// - When the live list holds fewer than [livePageSize] entries it is the
///   complete collection, so any base entry missing from it was deleted.
/// - Otherwise the live list only reaches back to its oldest entry. A base
///   entry newer than that point but missing from the live list was deleted
///   (undo, delete, refund). A base entry at or before that point is outside
///   the live window and is kept.
@visibleForTesting
Map<FinancialCategory, List<FinancialEntry>> mergeWeekEntries({
  required Map<FinancialCategory, List<FinancialEntry>> base,
  required Map<FinancialCategory, List<FinancialEntry>> live,
  required DateTime weekStart,
  required DateTime weekEnd,
  required int livePageSize,
}) {
  bool inWeek(FinancialEntry entry) =>
      !entry.createdAt.isBefore(weekStart) && entry.createdAt.isBefore(weekEnd);

  final merged = <FinancialCategory, List<FinancialEntry>>{};
  for (final category in FinancialCategory.values) {
    final liveEntries = live[category] ?? const <FinancialEntry>[];
    final liveIds = {for (final entry in liveEntries) entry.id};
    final result = <FinancialEntry>[
      for (final entry in liveEntries)
        if (inWeek(entry)) entry,
    ];

    final liveIsComplete = liveEntries.length < livePageSize;
    DateTime? oldestLive;
    if (!liveIsComplete) {
      oldestLive = liveEntries
          .map((entry) => entry.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
    }

    for (final entry in base[category] ?? const <FinancialEntry>[]) {
      if (!inWeek(entry) || liveIds.contains(entry.id)) continue;
      if (liveIsComplete) continue;
      if (entry.createdAt.isAfter(oldestLive!)) continue;
      result.add(entry);
    }
    merged[category] = result;
  }
  return merged;
}

class WeeklySpendingCard extends StatefulWidget {
  const WeeklySpendingCard({
    super.key,
    this.clock,
    this.retryDelay = const Duration(seconds: 2),
  });

  /// Source of the current time. Defaults to [DateTime.now]; tests override it.
  final DateTime Function()? clock;

  /// Pause before the single automatic retry after a failed load.
  final Duration retryDelay;

  @override
  State<WeeklySpendingCard> createState() => _WeeklySpendingCardState();
}

class _WeeklySpendingCardState extends State<WeeklySpendingCard>
    with WidgetsBindingObserver {
  /// Range-query result for the week in [_baseWeekStart]. It supplies entries
  /// older than the provider's live window; everything newer comes live.
  Map<FinancialCategory, List<FinancialEntry>> _base = {
    for (final category in FinancialCategory.values) category: [],
  };
  DateTime? _baseWeekStart;
  bool _loadFailed = false;
  bool _started = false;

  /// Incremented per load so a stale response can be ignored.
  int _generation = 0;
  Timer? _retryTimer;
  Timer? _midnightTimer;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  static DateTime _weekStartOf(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(today.year, today.month, today.day - (today.weekday - 1));
  }

  static DateTime _weekEndOf(DateTime weekStart) =>
      DateTime(weekStart.year, weekStart.month, weekStart.day + 7);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This runs on every BudgetProvider notification because build() watches
    // it. The guard keeps the range query to one call per trigger below.
    if (_started) return;
    _started = true;
    _scheduleMidnightCheck();
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    _scheduleMidnightCheck();
    // Redraw so the visible week follows the clock, then refetch the base
    // snapshot. A new week is picked up by the same refetch.
    setState(() {});
    unawaited(_load());
  }

  void _scheduleMidnightCheck() {
    _midnightTimer?.cancel();
    final now = _now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(
      nextMidnight.difference(now) + const Duration(seconds: 1),
      _onMidnight,
    );
  }

  void _onMidnight() {
    if (!mounted) return;
    _scheduleMidnightCheck();
    setState(() {});
    if (_baseWeekStart != _weekStartOf(_now())) unawaited(_load());
  }

  /// Fetches the base snapshot, with one automatic retry after a short pause.
  /// If the retry also fails, the card shows a quiet tap-to-retry state.
  Future<void> _load() async {
    if (!mounted) return;
    final budget = context.read<BudgetProvider>();
    final generation = ++_generation;
    _retryTimer?.cancel();

    if (await _tryFetch(budget, generation)) return;
    if (!mounted || generation != _generation) return;

    _retryTimer = Timer(widget.retryDelay, () async {
      if (!mounted || generation != _generation) return;
      final succeeded = await _tryFetch(budget, generation);
      if (!succeeded && mounted && generation == _generation) {
        setState(() => _loadFailed = true);
      }
    });
  }

  /// Returns false only when the query itself failed. A superseded or
  /// unmounted attempt counts as handled so it never schedules a retry.
  Future<bool> _tryFetch(BudgetProvider budget, int generation) async {
    final weekStart = _weekStartOf(_now());
    try {
      final entries = await budget.loadEntriesInRange(
        startInclusive: weekStart,
        endExclusive: _weekEndOf(weekStart),
      );
      if (!mounted || generation != _generation) return true;
      setState(() {
        _base = entries;
        _baseWeekStart = weekStart;
        _loadFailed = false;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _retry() {
    setState(() => _loadFailed = false);
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final budget = context.watch<BudgetProvider>();
    final weekStart = _weekStartOf(_now());
    final entries = mergeWeekEntries(
      base: _base,
      live: {
        for (final category in FinancialCategory.values)
          category: budget.entriesFor(category),
      },
      weekStart: weekStart,
      weekEnd: _weekEndOf(weekStart),
      livePageSize: FirestoreFinanceService.entryPageSize,
    );
    final days = budget.weeklySpendingForEntries(entries);
    final maxAmount = days.fold<double>(
      0,
      (max, day) => day.amount > max ? day.amount : max,
    );
    final hasSpending = maxAmount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Weekly Spending',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF121212),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Mon – Sun Overview',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 14),
          const _HeaderDivider(),
          const SizedBox(height: 22),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _DayBar(day: days[i], maxAmount: maxAmount),
                  ),
                ],
              ],
            ),
          ),
          if (_loadFailed) ...[
            const SizedBox(height: 12),
            Semantics(
              button: true,
              child: InkWell(
                onTap: _retry,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    'Couldn\'t refresh. Tap to retry.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
            ),
          ] else if (!hasSpending) ...[
            const SizedBox(height: 16),
            Text(
              'No spending recorded this week.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderDivider extends StatelessWidget {
  const _HeaderDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Container(
            height: 1.2,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: const Color(0xFFE5E7EB),
          ),
        ),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, required this.maxAmount});

  final WeeklyDaySpend day;
  final double maxAmount;

  static const double _chartHeight = 96;
  static const double _minBarHeight = 6;

  void _openDay(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DailySpendingPage(day: day.date)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final ratio = maxAmount <= 0
        ? 0.0
        : (day.amount / maxAmount).clamp(0.0, 1.0);
    final targetHeight = day.amount <= 0
        ? _minBarHeight
        : (_minBarHeight + ratio * (_chartHeight - _minBarHeight));

    final currencyProvider = context.watch<CurrencyProvider>();
    final currency = NumberFormat.currency(
      locale: currencyProvider.currency.locale,
      symbol: currencyProvider.symbol,
      decimalDigits: day.amount % 1 == 0 ? 0 : 2,
    ).format(day.amount);

    return Semantics(
      label: '${day.fullLabel}, $currency spent. Double tap to view details.',
      button: true,
      child: Tooltip(
        message: '${day.fullLabel}\n$currency',
        waitDuration: const Duration(milliseconds: 350),
        child: InkWell(
          onTap: () => _openDay(context),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: _chartHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: _minBarHeight,
                      end: targetHeight,
                    ),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 420),
                    curve: Curves.easeOutCubic,
                    builder: (context, height, _) {
                      return AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        width: double.infinity,
                        height: height,
                        decoration: BoxDecoration(
                          color: day.isToday
                              ? const Color(0xFF0A0A0A)
                              : const Color(0xFF1A1A1A),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10),
                          ),
                          border: day.isToday
                              ? Border.all(color: Colors.black, width: 1.2)
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                day.shortLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w600,
                  color: day.isToday
                      ? const Color(0xFF121212)
                      : const Color(0xFF6B7280),
                ),
              ),
              if (day.isToday) ...[
                const SizedBox(height: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: Color(0xFF121212),
                    shape: BoxShape.circle,
                  ),
                ),
              ] else
                const SizedBox(height: 9),
            ],
          ),
        ),
      ),
    );
  }
}
