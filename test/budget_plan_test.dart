import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/budget_plan.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/providers/notification_prefs_provider.dart';
import 'package:just_budget/services/planner_alert_store.dart';
import 'package:just_budget/widgets/planner_progress_bar.dart';

void main() {
  group('planner period boundaries', () {
    test('day covers only the chosen local date', () {
      final start = DateTime(2026, 10, 28);
      expect(PlannerPeriod.day.endExclusive(start), DateTime(2026, 10, 29));
    });

    test('week covers seven dates starting on the chosen date', () {
      final start = DateTime(2026, 10, 28);
      expect(PlannerPeriod.week.endExclusive(start), DateTime(2026, 11, 4));
    });

    test('month ends on the same date in the next month', () {
      final start = DateTime(2026, 10, 28);
      expect(PlannerPeriod.month.endExclusive(start), DateTime(2026, 11, 28));
    });

    test('month-end dates clamp to the next month end', () {
      expect(
        PlannerPeriod.month.endExclusive(DateTime(2027, 1, 31)),
        DateTime(2027, 2, 28),
      );
      expect(
        PlannerPeriod.month.endExclusive(DateTime(2028, 1, 31)),
        DateTime(2028, 2, 29),
      );
    });
  });

  test('total includes only switched-on categories', () {
    final amounts = {
      FinancialCategory.bills: 500.0,
      FinancialCategory.savings: 250.0,
      FinancialCategory.personal: 1000.0,
    };
    expect(
      plannerTotal({
        FinancialCategory.bills,
        FinancialCategory.personal,
      }, amounts),
      1500,
    );
    expect(plannerTotal({FinancialCategory.savings}, amounts), 250);
    expect(plannerTotal({}, amounts), 0);
  });

  test('planner category summary formats selected categories', () {
    expect(plannerCategorySummary({FinancialCategory.bills}), 'Bills');
    expect(
      plannerCategorySummary({
        FinancialCategory.bills,
        FinancialCategory.savings,
      }),
      'Bills & Savings',
    );
    expect(
      plannerCategorySummary(FinancialCategory.values.toSet()),
      'all categories',
    );
  });

  test(
    'save validation requires a positive amount for every enabled category',
    () {
      expect(isPlannerDraftValid({}, {}), isFalse);
      expect(
        isPlannerDraftValid(
          {FinancialCategory.bills},
          {FinancialCategory.bills: 0},
        ),
        isFalse,
      );
      expect(
        isPlannerDraftValid(
          {FinancialCategory.bills, FinancialCategory.personal},
          {FinancialCategory.bills: 500, FinancialCategory.personal: 0},
        ),
        isFalse,
      );
      expect(
        isPlannerDraftValid(
          {FinancialCategory.bills, FinancialCategory.personal},
          {FinancialCategory.bills: 500, FinancialCategory.personal: 1000},
        ),
        isTrue,
      );
    },
  );

  test('plan starting today counts today entries', () {
    final today = DateTime(2026, 10, 27);
    final plan = _plan(start: today, total: 500);
    final entries = {
      FinancialCategory.bills: [
        _entry('Electricity', 125, today.add(const Duration(hours: 9))),
      ],
    };

    expect(plannerSpent(plan, entries), 125);
  });

  test(
    'calendar-day plan counts entries logged before its saved start time',
    () {
      final savedStart = DateTime(2026, 10, 27, 16, 30);
      final plan = _plan(start: savedStart, total: 500);
      final entries = {
        FinancialCategory.bills: [
          _entry('Breakfast', 75, DateTime(2026, 10, 27, 8)),
        ],
      };

      expect(plan.localStart, DateTime(2026, 10, 27));
      expect(plannerSpent(plan, entries), 75);
    },
  );

  test('spent includes only categories enabled on the plan', () {
    final start = DateTime(2026, 10, 27);
    final plan = _plan(start: start, total: 500);
    final entries = {
      FinancialCategory.bills: [
        _entry('Electricity', 125, start.add(const Duration(hours: 9))),
      ],
      FinancialCategory.personal: [
        _entry('Lunch', 80, start.add(const Duration(hours: 12))),
      ],
    };

    expect(plannerSpent(plan, entries), 125);
  });

  test(
    'draft changes when a category is switched off and restores on switch on',
    () {
      final start = DateTime(2026, 10, 27);
      final saved = BudgetPlan(
        id: 'saved',
        period: PlannerPeriod.day,
        start: start,
        endExclusive: start.add(const Duration(days: 1)),
        amounts: const {
          FinancialCategory.bills: 500,
          FinancialCategory.personal: 300,
        },
        createdAt: start,
        alertEligible: true,
      );
      final switchedOff = BudgetPlan(
        id: 'draft',
        period: PlannerPeriod.day,
        start: start,
        endExclusive: start.add(const Duration(days: 1)),
        amounts: const {FinancialCategory.bills: 500},
        createdAt: start,
        alertEligible: true,
      );

      expect(plannerDraftDiffers(switchedOff, saved), isTrue);
      expect(plannerDraftDiffers(saved, saved), isFalse);
      expect(
        plannerSpent(switchedOff, {
          FinancialCategory.personal: [
            _entry('Lunch', 80, start.add(const Duration(hours: 12))),
          ],
        }),
        0,
      );
    },
  );

  test('future plan spends zero and reports its start date', () {
    final today = DateTime(2026, 10, 27, 12);
    final tomorrow = DateTime(2026, 10, 28);
    final plan = _plan(start: tomorrow, total: 500);
    final entries = {
      FinancialCategory.bills: [_entry('Electricity', 125, today)],
    };

    expect(plannerSpent(plan, entries), 0);
    expect(plannerStatusLabel(plan, 0, now: today), 'Starts Oct 28');
  });

  test('progress colors and minimum visible fill follow thresholds', () {
    expect(plannerProgressColor(0.79), const Color(0xFF16A34A));
    expect(plannerProgressColor(0.8), const Color(0xFFF59E0B));
    expect(plannerProgressColor(1), const Color(0xFFF59E0B));
    expect(plannerProgressColor(1.01), const Color(0xFFDC2626));
    expect(plannerProgressFillWidth(progress: 0, availableWidth: 100), 0);
    expect(plannerProgressFillWidth(progress: 0.001, availableWidth: 100), 4);
    expect(plannerProgressFillWidth(progress: 1.2, availableWidth: 100), 100);
  });

  test('planner system notification is skipped when setting is off', () {
    expect(
      plannerNotificationsAllowed(
        settingEnabled: false,
        permissionGranted: true,
      ),
      isFalse,
    );
    expect(
      plannerNotificationsAllowed(
        settingEnabled: true,
        permissionGranted: true,
      ),
      isTrue,
    );
  });

  test('planner notification preference defaults on per device', () {
    final prefs = NotificationPrefsProvider();
    expect(prefs.plannerEnabled, isTrue);
    prefs.dispose();
  });

  test(
    'spent excludes refunds, goal contributions, allocations, and dates outside the plan',
    () {
      final start = DateTime(2026, 10, 28);
      final plan = _plan(start: start, total: 1000, allCategories: true);
      final entries = {
        FinancialCategory.bills: [
          _entry('purchase', 100, start.add(const Duration(hours: 9))),
          _entry(
            'refund',
            90,
            start.add(const Duration(hours: 10)),
            isRefund: true,
          ),
          _entry('Received salary', 300, start.add(const Duration(hours: 11))),
          _entry('outside', 400, start.subtract(const Duration(minutes: 1))),
        ],
        FinancialCategory.savings: [
          _entry('Savings Goal', 200, start.add(const Duration(hours: 12))),
          _entry('Added money', 200, start.add(const Duration(hours: 13))),
        ],
        FinancialCategory.personal: [
          _entry('coffee', 50, start.add(const Duration(hours: 14))),
          _entry(
            'Allocation update',
            200,
            start.add(const Duration(hours: 15)),
          ),
        ],
      };

      expect(plannerSpent(plan, entries), 150);
    },
  );

  group('exceeded alert policy', () {
    test('exactly equal does not alert, strictly above does', () async {
      final tracker = PlannerAlertTracker(_MemoryAlertStore());
      final plan = _plan(total: 100);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 99), isFalse);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 100), isFalse);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 101), isTrue);
    });

    test('alerts only once per plan on a device', () async {
      final tracker = PlannerAlertTracker(_MemoryAlertStore());
      final plan = _plan(total: 100);
      await tracker.evaluate(uid: 'u', plan: plan, spent: 90);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 110), isTrue);
      await tracker.evaluate(uid: 'u', plan: plan, spent: 80);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 120), isFalse);
    });

    test('does not alert for an initial over-budget sync', () async {
      final tracker = PlannerAlertTracker(_MemoryAlertStore());
      final plan = _plan(total: 100);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 120), isFalse);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 130), isFalse);
    });

    test('a plan saved already exceeded is never eligible', () async {
      final tracker = PlannerAlertTracker(_MemoryAlertStore());
      final plan = _plan(total: 100, alertEligible: false);
      await tracker.evaluate(uid: 'u', plan: plan, spent: 90);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 120), isFalse);
    });

    test('clearing a deleted plan removes its local alert flag', () async {
      final store = _MemoryAlertStore();
      await store.markShown('u', 'deleted-plan');
      expect(await store.wasShown('u', 'deleted-plan'), isTrue);

      await store.clear('u', 'deleted-plan');

      expect(await store.wasShown('u', 'deleted-plan'), isFalse);
    });
  });
}

BudgetPlan _plan({
  DateTime? start,
  double total = 100,
  bool alertEligible = true,
  bool allCategories = false,
}) {
  final planStart = start ?? DateTime(2026, 10, 28);
  return BudgetPlan(
    id: 'plan-1',
    period: PlannerPeriod.day,
    start: planStart,
    endExclusive: planStart.add(const Duration(days: 1)),
    amounts: allCategories
        ? {
            FinancialCategory.bills: total / 3,
            FinancialCategory.savings: total / 3,
            FinancialCategory.personal: total / 3,
          }
        : {FinancialCategory.bills: total},
    createdAt: planStart,
    alertEligible: alertEligible,
  );
}

FinancialEntry _entry(
  String title,
  double amount,
  DateTime createdAt, {
  bool isRefund = false,
}) {
  return FinancialEntry(
    id: '$title-$createdAt',
    title: title,
    amount: amount,
    createdAt: createdAt,
    isRefund: isRefund,
  );
}

class _MemoryAlertStore implements PlannerAlertStore {
  final Set<String> _shown = {};

  @override
  Future<void> markShown(String uid, String planId) async {
    _shown.add('$uid|$planId');
  }

  @override
  Future<void> clear(String uid, String planId) async {
    _shown.remove('$uid|$planId');
  }

  @override
  Future<bool> wasShown(String uid, String planId) async {
    return _shown.contains('$uid|$planId');
  }
}
