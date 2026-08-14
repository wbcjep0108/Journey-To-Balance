import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/financial_entry.dart';
import '../providers/budget_provider.dart';

enum SpendingIntensity { none, minimal, average, significant }

class CategoryBreakdown {
  const CategoryBreakdown({
    required this.category,
    required this.amount,
    required this.percent,
  });

  final FinancialCategory category;
  final double amount;
  final double percent;
}

class MonthlySpendingStats {
  MonthlySpendingStats({
    required this.month,
    required this.dailyTotals,
    required this.total,
    required this.avgDaily,
    required this.highestDay,
    required this.lowestDays,
    required this.breakdown,
    required this.intensityByDay,
  });

  final DateTime month;
  final Map<DateTime, double> dailyTotals;
  final double total;
  final double avgDaily;
  final DateTime? highestDay;
  final List<DateTime> lowestDays;
  final List<CategoryBreakdown> breakdown;
  final Map<DateTime, SpendingIntensity> intensityByDay;

  factory MonthlySpendingStats.fromBudget({
    required BudgetProvider budget,
    required DateTime month,
  }) {
    final year = month.year;
    final monthIndex = month.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, monthIndex);
    final today = DateTime.now();
    final isCurrentMonth = year == today.year && monthIndex == today.month;
    final divisorDays = isCurrentMonth
        ? today.day.clamp(1, daysInMonth)
        : daysInMonth;

    final dailyTotals = <DateTime, double>{};
    final categoryTotals = <FinancialCategory, double>{
      for (final category in FinancialCategory.values) category: 0,
    };

    for (final category in FinancialCategory.values) {
      for (final entry in budget.entriesFor(category)) {
        if (entry.isRefund) continue;
        final local = entry.createdAt.toLocal();
        if (local.year != year || local.month != monthIndex) continue;
        final day = DateTime(local.year, local.month, local.day);
        dailyTotals[day] = (dailyTotals[day] ?? 0) + entry.amount;
        categoryTotals[category] =
            (categoryTotals[category] ?? 0) + entry.amount;
      }
    }

    var total = 0.0;
    for (final amount in dailyTotals.values) {
      total += amount;
    }

    final avgDaily = divisorDays > 0 ? total / divisorDays : 0.0;

    DateTime? highestDay;
    var highestAmount = -1.0;
    for (final entry in dailyTotals.entries) {
      if (entry.value > highestAmount) {
        highestAmount = entry.value;
        highestDay = entry.key;
      }
    }

    final spendingDays = dailyTotals.entries
        .where((e) => e.value > 0)
        .toList();
    final lowestDays = <DateTime>[];
    if (spendingDays.isNotEmpty) {
      var minAmount = spendingDays.first.value;
      for (final entry in spendingDays) {
        if (entry.value < minAmount) minAmount = entry.value;
      }
      for (final entry in spendingDays) {
        if ((entry.value - minAmount).abs() < 0.001) {
          lowestDays.add(entry.key);
        }
      }
      lowestDays.sort();
    }

    final breakdown = <CategoryBreakdown>[];
    for (final category in FinancialCategory.values) {
      final amount = categoryTotals[category] ?? 0;
      if (amount <= 0) continue;
      breakdown.add(
        CategoryBreakdown(
          category: category,
          amount: amount,
          percent: total > 0 ? (amount / total) * 100 : 0,
        ),
      );
    }
    breakdown.sort((a, b) => b.amount.compareTo(a.amount));

    final intensityByDay = <DateTime, SpendingIntensity>{};
    final positiveAmounts =
        spendingDays.map((e) => e.value).toList()..sort();
    double? t1;
    double? t2;
    if (positiveAmounts.length >= 3) {
      t1 = positiveAmounts[(positiveAmounts.length / 3).floor().clamp(
        0,
        positiveAmounts.length - 1,
      )];
      t2 = positiveAmounts[((positiveAmounts.length * 2) / 3).floor().clamp(
        0,
        positiveAmounts.length - 1,
      )];
    } else if (positiveAmounts.length == 2) {
      t1 = positiveAmounts.first;
      t2 = positiveAmounts.last;
    } else if (positiveAmounts.length == 1) {
      t1 = positiveAmounts.first;
      t2 = positiveAmounts.first;
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, monthIndex, day);
      final amount = dailyTotals[date] ?? 0;
      if (amount <= 0 || t1 == null || t2 == null) {
        intensityByDay[date] = SpendingIntensity.none;
      } else if (amount <= t1 + 0.001) {
        intensityByDay[date] = SpendingIntensity.minimal;
      } else if (amount <= t2 + 0.001) {
        intensityByDay[date] = SpendingIntensity.average;
      } else {
        intensityByDay[date] = SpendingIntensity.significant;
      }
    }

    return MonthlySpendingStats(
      month: DateTime(year, monthIndex),
      dailyTotals: dailyTotals,
      total: total,
      avgDaily: avgDaily,
      highestDay: highestDay,
      lowestDays: lowestDays,
      breakdown: breakdown,
      intensityByDay: intensityByDay,
    );
  }

  String get monthYearLabel => DateFormat('MMMM yyyy').format(month);

  String get summaryMonthLabel {
    final short = DateFormat("MMM ''yy").format(month).toUpperCase();
    return 'SUMMARY ($short)';
  }
}

String categoryDashboardLabel(FinancialCategory category) {
  return switch (category) {
    FinancialCategory.bills => 'Bills',
    FinancialCategory.savings => 'Savings',
    FinancialCategory.personal => 'Personal',
  };
}

String categoryIconAsset(FinancialCategory category) {
  return switch (category) {
    FinancialCategory.bills => 'assets/images/icons/bills.png',
    FinancialCategory.savings => 'assets/images/icons/savings.png',
    FinancialCategory.personal => 'assets/images/icons/personal.png',
  };
}
