import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/budget_plan.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/services/planner_firestore_service.dart';

/// Local midnight as the RFC 3339 UTC text the old Worker wrote back.
String _workerText(DateTime local) => local.toUtc().toIso8601String();

/// A three-day Day plan, Oct 28 to Oct 30, with every date stored as text.
Map<String, dynamic> _textPlanner() => {
  'id': 'plan-1',
  'period': 'day',
  'startAt': _workerText(DateTime(2026, 10, 28)),
  'endAt': _workerText(DateTime(2026, 10, 31)),
  'endDate': _workerText(DateTime(2026, 10, 30)),
  'createdAt': '2026-10-27T03:15:42.123456789Z',
  'billsEnabled': true,
  'billsAmount': 900,
  'savingsEnabled': false,
  'savingsAmount': 0,
  'personalEnabled': false,
  'personalAmount': 0,
  'total': 900,
  'alertEligible': true,
  'thirteenthMonth': {
    'year': 2026,
    'monthlyBasicSalaries': List<int>.filled(12, 24500),
    'otherBenefits': 0,
    'updatedAt': '2026-10-20T08:00:00Z',
  },
};

void main() {
  group('plan with text dates', () {
    test('loads the stored range, not today', () {
      final plan = BudgetPlan.fromFirestore(_textPlanner());

      expect(plan.localStart, DateTime(2026, 10, 28));
      expect(plan.localEndDate, DateTime(2026, 10, 30));
      expect(plan.localEndExclusive, DateTime(2026, 10, 31));
      expect(plan.dayCount, 3);
      expect(plan.createdAt.toUtc(), DateTime.utc(2026, 10, 27, 3, 15, 42, 123, 456));
      expect(plannerPeriodSummary(plan), 'Oct 28 - Oct 30 - 3-day plan');
    });

    test('counts spending in the stored range only', () {
      final plan = BudgetPlan.fromFirestore(_textPlanner());
      FinancialEntry entry(String id, DateTime at) =>
          FinancialEntry(id: id, title: 'Lunch', amount: 10, createdAt: at);

      final spent = plannerSpent(plan, {
        FinancialCategory.bills: [
          entry('before', DateTime(2026, 10, 27, 23)),
          entry('first', DateTime(2026, 10, 28, 9)),
          entry('last', DateTime(2026, 10, 30, 22)),
          entry('after', DateTime(2026, 10, 31, 1)),
        ],
      });
      expect(spent, 20);
    });

    test('a week plan with text dates keeps its seven-day range', () {
      final data = _textPlanner()
        ..['period'] = 'week'
        ..['endAt'] = _workerText(DateTime(2026, 11, 4))
        ..remove('endDate');
      final plan = BudgetPlan.fromFirestore(data);
      expect(plan.localStart, DateTime(2026, 10, 28));
      expect(plan.localEndExclusive, DateTime(2026, 11, 4));
    });

    test('mixed timestamps and text load the same range', () {
      final data = _textPlanner()
        ..['startAt'] = Timestamp.fromDate(DateTime(2026, 10, 28));
      expect(
        BudgetPlan.fromFirestore(data).localEndExclusive,
        DateTime(2026, 10, 31),
      );
    });

    test('unreadable text is rejected instead of becoming today', () {
      final data = _textPlanner()..['startAt'] = 'not a date';
      expect(() => BudgetPlan.fromFirestore(data), throwsFormatException);
      expect(() => plannerStoredDate('garbage'), throwsFormatException);
      expect(plannerStoredDate(null), isNull);
    });
  });

  group('saving a plan', () {
    final plan = BudgetPlan(
      id: 'plan-2',
      period: PlannerPeriod.week,
      start: DateTime(2026, 11, 2),
      endExclusive: DateTime(2026, 11, 9),
      amounts: const {FinancialCategory.bills: 500},
      createdAt: DateTime(2026, 11, 1, 10),
      alertEligible: true,
    );

    test('writes every plan date as a real timestamp', () {
      final saved = plan.toFirestore();

      expect(saved['startAt'], Timestamp.fromDate(DateTime(2026, 11, 2)));
      expect(saved['endAt'], Timestamp.fromDate(DateTime(2026, 11, 9)));
      expect(saved['createdAt'], Timestamp.fromDate(DateTime(2026, 11, 1, 10)));
      // A Week plan clears any old end date.
      expect(saved['endDate'], isA<FieldValue>());
    });

    test('writes only Budget Planner fields, never 13th Month Pay data', () {
      final saved = plan.toFirestore();

      expect(saved.containsKey('thirteenthMonth'), isFalse);
      expect(saved.keys.toSet(), plannerPlanFields.toSet());
    });
  });
}