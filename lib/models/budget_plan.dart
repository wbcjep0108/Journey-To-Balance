import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'financial_entry.dart';

enum PlannerPeriod { day, week, month }

extension PlannerPeriodX on PlannerPeriod {
  String get label => switch (this) {
    PlannerPeriod.day => 'Day',
    PlannerPeriod.week => 'Week',
    PlannerPeriod.month => 'Month',
  };

  String get planLabel => switch (this) {
    PlannerPeriod.day => 'Daily plan',
    PlannerPeriod.week => 'Weekly plan',
    PlannerPeriod.month => 'Monthly plan',
  };

  DateTime endExclusive(DateTime start) {
    final normalized = DateUtils.dateOnly(start);
    return switch (this) {
      PlannerPeriod.day => normalized.add(const Duration(days: 1)),
      PlannerPeriod.week => normalized.add(const Duration(days: 7)),
      PlannerPeriod.month => _sameDayNextMonth(normalized),
    };
  }

  static DateTime _sameDayNextMonth(DateTime start) {
    final nextMonth = DateTime(start.year, start.month + 1);
    final lastDay = DateUtils.getDaysInMonth(nextMonth.year, nextMonth.month);
    return DateTime(
      nextMonth.year,
      nextMonth.month,
      start.day.clamp(1, lastDay),
    );
  }
}

class BudgetPlan {
  const BudgetPlan({
    required this.id,
    required this.period,
    required this.start,
    required this.endExclusive,
    required this.amounts,
    required this.createdAt,
    required this.alertEligible,
  });

  final String id;
  final PlannerPeriod period;
  final DateTime start;
  final DateTime endExclusive;
  final Map<FinancialCategory, double> amounts;
  final DateTime createdAt;
  final bool alertEligible;

  Set<FinancialCategory> get enabledCategories => amounts.entries
      .where((entry) => entry.value > 0)
      .map((entry) => entry.key)
      .toSet();

  double get total => amounts.values.fold(0, (total, amount) => total + amount);

  DateTime get localStart => DateUtils.dateOnly(start.toLocal());

  DateTime get localEndExclusive => period.endExclusive(localStart);

  bool get hasEnded => !DateTime.now().isBefore(localEndExclusive);

  bool get hasStarted => !DateTime.now().isBefore(localStart);

  Map<String, Object?> toFirestore() {
    return {
      'id': id,
      'period': period.name,
      'startAt': Timestamp.fromDate(start),
      'endAt': Timestamp.fromDate(endExclusive),
      'billsEnabled': amounts.containsKey(FinancialCategory.bills),
      'billsAmount': amounts[FinancialCategory.bills] ?? 0,
      'savingsEnabled': amounts.containsKey(FinancialCategory.savings),
      'savingsAmount': amounts[FinancialCategory.savings] ?? 0,
      'personalEnabled': amounts.containsKey(FinancialCategory.personal),
      'personalAmount': amounts[FinancialCategory.personal] ?? 0,
      'total': total,
      'createdAt': Timestamp.fromDate(createdAt),
      'alertEligible': alertEligible,
    };
  }

  factory BudgetPlan.fromFirestore(Map<String, dynamic> data) {
    final periodName = data['period'] as String?;
    final period = PlannerPeriod.values.firstWhere(
      (value) => value.name == periodName,
      orElse: () => PlannerPeriod.day,
    );
    final startAt = data['startAt'];
    final endAt = data['endAt'];
    final createdAt = data['createdAt'];
    final amounts = <FinancialCategory, double>{};
    if (data['billsEnabled'] == true) {
      amounts[FinancialCategory.bills] =
          (data['billsAmount'] as num?)?.toDouble() ?? 0;
    }
    if (data['savingsEnabled'] == true) {
      amounts[FinancialCategory.savings] =
          (data['savingsAmount'] as num?)?.toDouble() ?? 0;
    }
    if (data['personalEnabled'] == true) {
      amounts[FinancialCategory.personal] =
          (data['personalAmount'] as num?)?.toDouble() ?? 0;
    }
    return BudgetPlan(
      id: data['id'] as String? ?? '',
      period: period,
      start: (startAt is Timestamp ? startAt.toDate() : DateTime.now())
          .toLocal(),
      endExclusive:
          (endAt is Timestamp
                  ? endAt.toDate()
                  : period.endExclusive(DateTime.now()))
              .toLocal(),
      amounts: amounts,
      createdAt: (createdAt is Timestamp ? createdAt.toDate() : DateTime.now())
          .toLocal(),
      alertEligible: data['alertEligible'] == true,
    );
  }
}

double plannerTotal(
  Set<FinancialCategory> enabled,
  Map<FinancialCategory, double> amounts,
) {
  return enabled.fold(0, (total, category) => total + (amounts[category] ?? 0));
}

bool isPlannerDraftValid(
  Set<FinancialCategory> enabled,
  Map<FinancialCategory, double> amounts,
) {
  return enabled.isNotEmpty &&
      enabled.every((category) => (amounts[category] ?? 0) > 0);
}

bool plannerDraftDiffers(BudgetPlan draft, BudgetPlan? saved) {
  if (saved == null) return draft.amounts.isNotEmpty;
  if (draft.period != saved.period ||
      draft.localStart != saved.localStart ||
      draft.amounts.length != saved.amounts.length) {
    return true;
  }
  for (final entry in draft.amounts.entries) {
    final savedAmount = saved.amounts[entry.key];
    if (savedAmount == null || (entry.value - savedAmount).abs() > 0.001) {
      return true;
    }
  }
  return false;
}

String plannerCategorySummary(Set<FinancialCategory> categories) {
  const labels = {
    FinancialCategory.bills: 'Bills',
    FinancialCategory.savings: 'Savings',
    FinancialCategory.personal: 'Personal',
  };
  final selected = FinancialCategory.values
      .where(categories.contains)
      .map((category) => labels[category]!)
      .toList();
  if (selected.length == FinancialCategory.values.length) {
    return 'all categories';
  }
  return selected.join(' & ');
}

bool isPlannerPurchase(FinancialEntry entry) {
  if (entry.isRefund || entry.amount <= 0) return false;
  return entry.title != 'Savings Goal' &&
      entry.title != 'Received salary' &&
      entry.title != 'Added money' &&
      entry.title != 'Allocation update';
}

double plannerSpent(
  BudgetPlan plan,
  Map<FinancialCategory, List<FinancialEntry>> entries,
) {
  var spent = 0.0;
  for (final category in plan.enabledCategories) {
    for (final entry in entries[category] ?? const <FinancialEntry>[]) {
      if (!isPlannerPurchase(entry)) continue;
      final local = entry.createdAt.toLocal();
      if (!local.isBefore(plan.localStart) &&
          local.isBefore(plan.localEndExclusive)) {
        spent += entry.amount;
      }
    }
  }
  return spent;
}

String plannerFriendlyDate(DateTime value, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final date = DateUtils.dateOnly(value);
  if (date == today) return 'Today';
  if (date == today.add(const Duration(days: 1))) {
    return 'Tomorrow, ${DateFormat('MMM d').format(date)}';
  }
  return DateFormat('MMM d, y').format(date);
}

String plannerPeriodSummary(BudgetPlan plan) {
  final start = DateFormat('MMM d').format(plan.localStart);
  if (plan.period == PlannerPeriod.day) {
    return '$start - ${plan.period.planLabel}';
  }
  final end = DateFormat(
    'MMM d',
  ).format(plan.localEndExclusive.subtract(const Duration(days: 1)));
  return '$start - $end - ${plan.period.planLabel}';
}

String plannerStatusLabel(BudgetPlan plan, double spent, {DateTime? now}) {
  final current = now ?? DateTime.now();
  if (current.isBefore(plan.localStart)) {
    return 'Starts ${DateFormat('MMM d').format(plan.localStart)}';
  }
  if (!current.isBefore(plan.localEndExclusive)) {
    return spent > plan.total ? 'Exceeded' : 'Within budget';
  }
  return plannerPeriodSummary(plan);
}

String plannerAlertPlanLabel(BudgetPlan plan, {DateTime? now}) {
  final current = DateUtils.dateOnly(now ?? DateTime.now());
  return switch (plan.period) {
    PlannerPeriod.day =>
      '${current == plan.localStart ? "Today's" : "Daily"} plan - '
          '${DateFormat('MMM d').format(plan.localStart)}',
    PlannerPeriod.week => "This week's plan",
    PlannerPeriod.month => "This month's plan",
  };
}
