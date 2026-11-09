import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/app_currency.dart';
import 'package:just_budget/models/budget_plan.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/providers/budget_provider.dart';
import 'package:just_budget/providers/currency_provider.dart';
import 'package:just_budget/providers/notification_prefs_provider.dart';
import 'package:just_budget/providers/planner_provider.dart';
import 'package:just_budget/services/finance_api_service.dart';
import 'package:just_budget/services/firestore_finance_service.dart';
import 'package:just_budget/services/notification_service.dart';
import 'package:just_budget/services/planner_alert_store.dart';
import 'package:just_budget/services/planner_firestore_service.dart';

final _start = DateTime(2026, 10, 28);
final _oct30 = DateTime(2026, 10, 30);

BudgetPlan _plan({
  DateTime? endDate,
  PlannerPeriod period = PlannerPeriod.day,
  double total = 300,
  String id = 'p',
}) {
  return BudgetPlan(
    id: id,
    period: period,
    start: _start,
    endExclusive: plannerEndExclusive(period, _start, endDate),
    amounts: {FinancialCategory.bills: total},
    createdAt: _start,
    alertEligible: true,
    endDate: endDate,
  );
}

FinancialEntry _entry(String title, double amount, DateTime at) {
  return FinancialEntry(
    id: '$title-$at',
    title: title,
    amount: amount,
    createdAt: at,
  );
}

Map<String, dynamic> _stored({
  String period = 'day',
  DateTime? endDate,
  DateTime? endAt,
}) {
  return {
    'id': 'p',
    'period': period,
    'startAt': Timestamp.fromDate(_start),
    'endAt': Timestamp.fromDate(endAt ?? DateTime(2026, 10, 29)),
    'billsEnabled': true,
    'billsAmount': 300,
    'createdAt': Timestamp.fromDate(_start),
    'alertEligible': true,
    if (endDate != null) 'endDate': Timestamp.fromDate(endDate),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Day plan without an end date', () {
    test('behaves as a one-day plan', () {
      final plan = _plan();
      expect(plan.localEndDate, isNull);
      expect(plan.isMultiDay, isFalse);
      expect(plan.dayCount, 1);
      expect(plan.localEndExclusive, DateTime(2026, 10, 29));
      expect(plannerPeriodSummary(plan), 'Oct 28 - Daily plan');
      expect(plannerPerDayAmount(plan), isNull);
      expect(
        plannerAlertPlanLabel(plan, now: DateTime(2026, 10, 28)),
        "Today's plan - Oct 28",
      );
    });

    test('clears any stored end date when saved with merge', () {
      expect(_plan().toFirestore()['endDate'], isA<FieldValue>());
    });
  });

  group('three-day Day plan, Oct 28 to Oct 30', () {
    final plan = _plan(endDate: _oct30, total: 300);

    test('covers the start date through the end of the end date', () {
      expect(plan.localEndDate, _oct30);
      expect(plan.isMultiDay, isTrue);
      expect(plan.dayCount, 3);
      expect(plan.localEndExclusive, DateTime(2026, 10, 31));
    });

    test('counts spending across all three days and nothing outside', () {
      final entries = {
        FinancialCategory.bills: [
          _entry('before', 1000, DateTime(2026, 10, 27, 23, 59)),
          _entry('first', 10, DateTime(2026, 10, 28)),
          _entry('middle', 20, DateTime(2026, 10, 29, 12)),
          _entry('last', 30, DateTime(2026, 10, 30, 23, 59)),
          _entry('after', 1000, DateTime(2026, 10, 31)),
        ],
      };
      expect(plannerSpent(plan, entries), 60);
    });

    test('labels the range, the per-day amount, and the alert title', () {
      expect(plannerPeriodSummary(plan), 'Oct 28 - Oct 30 - 3-day plan');
      expect(plannerPerDayAmount(plan), 100);
      expect(
        plannerAlertPlanLabel(plan, now: DateTime(2026, 10, 28)),
        'This plan - Oct 28 - Oct 30',
      );
    });

    test('keeps "Starts" before the start and the final result after', () {
      expect(
        plannerStatusLabel(plan, 0, now: DateTime(2026, 10, 27, 12)),
        'Starts Oct 28',
      );
      expect(
        plannerStatusLabel(plan, 10, now: DateTime(2026, 10, 29, 12)),
        'Oct 28 - Oct 30 - 3-day plan',
      );
      expect(
        plannerStatusLabel(plan, 300, now: DateTime(2026, 10, 31)),
        'Within budget',
      );
      expect(
        plannerStatusLabel(plan, 301, now: DateTime(2026, 10, 31)),
        'Exceeded',
      );
    });

    test('is saved with the end date and an exclusive end after it', () {
      final stored = plan.toFirestore();
      expect(stored['endDate'], Timestamp.fromDate(_oct30));
      expect(stored['endAt'], Timestamp.fromDate(DateTime(2026, 10, 31)));
    });

    test('the draft differs from a saved plan when only the range changes', () {
      expect(plannerDraftDiffers(plan, plan), isFalse);
      expect(plannerDraftDiffers(plan, _plan()), isTrue);
      expect(
        plannerDraftDiffers(plan, _plan(endDate: DateTime(2026, 10, 29))),
        isTrue,
      );
    });
  });

  group('range validation', () {
    test('rejects an end before the start and ranges over six days', () {
      expect(isPlannerDayRangeValid(_start, null), isTrue);
      expect(isPlannerDayRangeValid(_start, _start), isTrue);
      expect(isPlannerDayRangeValid(_start, DateTime(2026, 10, 27)), isFalse);
      expect(isPlannerDayRangeValid(_start, DateTime(2026, 11, 2)), isTrue);
      expect(isPlannerDayRangeValid(_start, DateTime(2026, 11, 3)), isFalse);
    });

    test('a model with an invalid end date falls back to one day', () {
      final tooLong = _plan(endDate: DateTime(2026, 11, 3));
      expect(tooLong.localEndDate, isNull);
      expect(tooLong.dayCount, 1);
      final backwards = _plan(endDate: DateTime(2026, 10, 27));
      expect(backwards.localEndDate, isNull);
    });

    test('week and month ignore an end date and keep their boundaries', () {
      final week = _plan(period: PlannerPeriod.week, endDate: _oct30);
      expect(week.localEndDate, isNull);
      expect(week.localEndExclusive, DateTime(2026, 11, 4));
      final month = _plan(period: PlannerPeriod.month, endDate: _oct30);
      expect(month.localEndDate, isNull);
      expect(month.localEndExclusive, DateTime(2026, 11, 28));
      expect(plannerPeriodSummary(week), 'Oct 28 - Nov 3 - Weekly plan');
    });

    test('range helpers count and extend calendar days', () {
      expect(plannerRangeDays(_start, _start), 1);
      expect(plannerRangeDays(_start, _oct30), 3);
      expect(plannerDayRangeEnd(_start, 3), _oct30);
      expect(plannerDayRangeEnd(DateTime(2026, 10, 30), 3), DateTime(2026, 11, 1));
    });
  });

  group('loading a saved plan', () {
    test('a plan without an end date loads as a one-day plan', () {
      final plan = BudgetPlan.fromFirestore(_stored());
      expect(plan.period, PlannerPeriod.day);
      expect(plan.endDate, isNull);
      expect(plan.dayCount, 1);
      expect(plan.localEndExclusive, DateTime(2026, 10, 29));
    });

    test('a Day plan with an end date loads as a multi-day plan', () {
      final plan = BudgetPlan.fromFirestore(
        _stored(endDate: _oct30, endAt: DateTime(2026, 10, 31)),
      );
      expect(plan.localEndDate, _oct30);
      expect(plan.dayCount, 3);
    });

    test('an unknown period loads as a Day plan with no end date', () {
      final plan = BudgetPlan.fromFirestore(
        _stored(period: 'fortnight', endDate: _oct30, endAt: DateTime(2026, 10, 31)),
      );
      expect(plan.period, PlannerPeriod.day);
      expect(plan.endDate, isNull);
      expect(plan.dayCount, 1);
    });

    test('a Week plan ignores a stored end date', () {
      final plan = BudgetPlan.fromFirestore(
        _stored(period: 'week', endDate: _oct30, endAt: DateTime(2026, 10, 31)),
      );
      expect(plan.period, PlannerPeriod.week);
      expect(plan.endDate, isNull);
      expect(plan.localEndExclusive, DateTime(2026, 11, 4));
    });

    test('a stale end date that disagrees with endAt is dropped', () {
      final plan = BudgetPlan.fromFirestore(
        _stored(endDate: _oct30, endAt: DateTime(2026, 10, 29)),
      );
      expect(plan.endDate, isNull);
      expect(plan.dayCount, 1);
    });

    test('an end date before the start or over six days is dropped', () {
      final before = BudgetPlan.fromFirestore(
        _stored(endDate: DateTime(2026, 10, 27), endAt: DateTime(2026, 10, 28)),
      );
      expect(before.endDate, isNull);
      final tooLong = BudgetPlan.fromFirestore(
        _stored(endDate: DateTime(2026, 11, 3), endAt: DateTime(2026, 11, 4)),
      );
      expect(tooLong.endDate, isNull);
    });
  });

  group('exceeded alert across a range', () {
    final plan = _plan(endDate: _oct30, total: 100);

    double spentAfter(List<double> perDay) {
      final days = [DateTime(2026, 10, 28), DateTime(2026, 10, 29), _oct30];
      return plannerSpent(plan, {
        FinancialCategory.bills: [
          for (var i = 0; i < perDay.length; i++)
            _entry('day$i', perDay[i], days[i].add(const Duration(hours: 9))),
        ],
      });
    }

    test('fires once when the range total goes strictly above the budget', () async {
      final tracker = PlannerAlertTracker(_MemoryAlertStore());
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 0), isFalse);
      expect(
        await tracker.evaluate(uid: 'u', plan: plan, spent: spentAfter([60])),
        isFalse,
      );
      expect(
        await tracker.evaluate(uid: 'u', plan: plan, spent: spentAfter([60, 40])),
        isFalse,
      );
      expect(
        await tracker.evaluate(uid: 'u', plan: plan, spent: spentAfter([60, 40, 1])),
        isTrue,
      );
      expect(
        await tracker.evaluate(uid: 'u', plan: plan, spent: spentAfter([60, 40, 50])),
        isFalse,
      );
    });

    test('does not fire on startup when the range is already over', () async {
      final tracker = PlannerAlertTracker(_MemoryAlertStore());
      expect(
        await tracker.evaluate(
          uid: 'u',
          plan: plan,
          spent: spentAfter([80, 80]),
        ),
        isFalse,
      );
    });

    test('a plan saved again with a new range counts as a new plan', () async {
      final store = _MemoryAlertStore();
      final tracker = PlannerAlertTracker(store);
      await tracker.evaluate(uid: 'u', plan: plan, spent: 50);
      expect(await tracker.evaluate(uid: 'u', plan: plan, spent: 120), isTrue);

      final edited = _plan(endDate: DateTime(2026, 10, 29), total: 100, id: 'p2');
      await tracker.evaluate(uid: 'u', plan: edited, spent: 50);
      expect(await tracker.evaluate(uid: 'u', plan: edited, spent: 120), isTrue);
    });
  });

  group('PlannerProvider.savePlan', () {
    late _RangeService service;
    late _RangeBudget budget;
    late PlannerProvider planner;

    setUp(() async {
      service = _RangeService();
      budget = _RangeBudget();
      planner = PlannerProvider(
        service,
        budget,
        _PlainCurrency(),
        NotificationPrefsProvider(),
        alertStore: _MemoryAlertStore(),
        notifications: _QuietNotifications(),
      );
      await planner.loadForUser('user-1');
    });

    tearDown(() {
      planner.dispose();
      budget.dispose();
    });

    Future<void> save({
      PlannerPeriod period = PlannerPeriod.day,
      DateTime? endDate,
      double amount = 300,
    }) {
      return planner.savePlan(
        period: period,
        start: _start,
        endDate: endDate,
        enabled: {FinancialCategory.bills},
        amounts: {FinancialCategory.bills: amount},
      );
    }

    test('saves a three-day plan with its end date and exclusive end', () async {
      await save(endDate: _oct30);
      final saved = service.saved!;
      expect(saved.endDate, _oct30);
      expect(saved.endExclusive, DateTime(2026, 10, 31));
      expect(budget.lastStart, _start);
      expect(budget.lastEnd, DateTime(2026, 10, 31));
    });

    test('an end date equal to the start saves a one-day plan', () async {
      await save(endDate: _start);
      expect(service.saved!.endDate, isNull);
      expect(service.saved!.endExclusive, DateTime(2026, 10, 29));
    });

    test('rejects an end before the start', () async {
      await expectLater(
        save(endDate: DateTime(2026, 10, 27)),
        throwsArgumentError,
      );
      expect(service.saved, isNull);
    });

    test('rejects a Day range longer than six days', () async {
      await expectLater(
        save(endDate: DateTime(2026, 11, 3)),
        throwsArgumentError,
      );
      expect(service.saved, isNull);
      await save(endDate: DateTime(2026, 11, 2));
      expect(service.saved!.dayCount, 6);
    });

    test('Week and Month saves drop the end date', () async {
      await save(period: PlannerPeriod.week, endDate: _oct30);
      expect(service.saved!.endDate, isNull);
      expect(service.saved!.endExclusive, DateTime(2026, 11, 4));
      await save(period: PlannerPeriod.month, endDate: _oct30);
      expect(service.saved!.endDate, isNull);
      expect(service.saved!.endExclusive, DateTime(2026, 11, 28));
    });

    test('a range already over budget is not alert eligible', () async {
      budget.entries = {
        FinancialCategory.bills: [
          _entry('a', 60, DateTime(2026, 10, 28, 9)),
          _entry('b', 60, DateTime(2026, 10, 29, 9)),
          _entry('outside', 500, DateTime(2026, 10, 31, 9)),
        ],
      };
      await save(endDate: _oct30, amount: 100);
      expect(service.saved!.alertEligible, isFalse);

      await save(endDate: _oct30, amount: 300);
      expect(service.saved!.alertEligible, isTrue);
    });
  });
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

class _RangeService implements PlannerFirestoreService {
  BudgetPlan? saved;
  int _ids = 0;

  @override
  Future<BudgetPlan?> load(String uid) async => null;

  @override
  Stream<PlannerSnapshot> watch(String uid) => const Stream.empty();

  @override
  String createPlanId(String uid) => 'plan-${++_ids}';

  @override
  Future<void> save(String uid, BudgetPlan plan) async {
    saved = plan;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubService implements FirestoreFinanceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubApi implements FinanceApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RangeBudget extends BudgetProvider {
  _RangeBudget() : super(_StubService(), financeApi: _StubApi());

  Map<FinancialCategory, List<FinancialEntry>> entries = {};
  DateTime? lastStart;
  DateTime? lastEnd;

  @override
  Future<Map<FinancialCategory, List<FinancialEntry>>> loadEntriesInRange({
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) async {
    lastStart = startInclusive;
    lastEnd = endExclusive;
    return entries;
  }
}

class _PlainCurrency extends ChangeNotifier implements CurrencyProvider {
  @override
  AppCurrency get currency => AppCurrency.php;

  @override
  String get symbol => 'PHP';

  @override
  String formatAmount(double amount, {String pattern = '#,##0.##'}) =>
      'PHP ${amount.toStringAsFixed(2)}';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _QuietNotifications implements NotificationService {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
