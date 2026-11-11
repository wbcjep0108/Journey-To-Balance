import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/budget_plan.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/providers/budget_provider.dart';
import 'package:just_budget/providers/thirteenth_month_provider.dart';
import 'package:just_budget/services/finance_api_service.dart';
import 'package:just_budget/services/firestore_finance_service.dart';
import 'package:just_budget/services/planner_firestore_service.dart';
import 'package:just_budget/services/thirteenth_month_firestore_service.dart';

/// The damaged record found on device: no salaries, text updatedAt.
const _damagedLegacy = {
  'year': 2026,
  'otherBenefits': 0,
  'updatedAt': '2026-11-10T02:54:48.692Z',
};

final _completeLegacy = {
  'year': 2026,
  'monthlyBasicSalaries': List<int>.filled(12, 24500),
  'otherBenefits': 1500,
  'updatedAt': Timestamp.fromDate(DateTime(2026, 11, 1)),
};

class _StubService implements FirestoreFinanceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubApi implements FinanceApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCalculatorStore implements ThirteenthMonthFirestoreService {
  _FakeCalculatorStore({this.stored, this.failSave = false});

  ThirteenthMonthInputs? stored;
  final bool failSave;
  final List<List<double>> saves = [];

  @override
  Future<ThirteenthMonthInputs?> load(String uid) async => stored;

  @override
  Future<void> save(
    String uid, {
    required List<double> monthlySalaries,
    required double otherBenefits,
  }) async {
    if (failSave) throw StateError('calculator write rejected');
    saves.add(List<double>.from(monthlySalaries));
    stored = ThirteenthMonthInputs(
      monthlySalaries: monthlySalaries,
      otherBenefits: otherBenefits,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('13th Month Pay inputs are read leniently', () {
    test('a complete record loads unchanged', () {
      final inputs = parseThirteenthMonthInputs(_completeLegacy)!;
      expect(inputs.monthlySalaries, List<double>.filled(12, 24500));
      expect(inputs.otherBenefits, 1500);
    });

    test('a record with no salaries keeps other benefits and shows zeros', () {
      final inputs = parseThirteenthMonthInputs({
        ..._damagedLegacy,
        'otherBenefits': 800,
      })!;
      expect(inputs.monthlySalaries, List<double>.filled(12, 0));
      expect(inputs.otherBenefits, 800);
    });

    test('a short or non-numeric salary list keeps the values it has', () {
      final inputs = parseThirteenthMonthInputs({
        'monthlyBasicSalaries': [20000, 'x', -5, 21000],
        'otherBenefits': 'bad',
      })!;
      expect(inputs.monthlySalaries.length, 12);
      expect(inputs.monthlySalaries.take(4), [20000, 0, 0, 21000]);
      expect(inputs.otherBenefits, 0);
    });

    test('missing, absent, or unusable data loads as nothing', () {
      expect(parseThirteenthMonthInputs(null), isNull);
      expect(parseThirteenthMonthInputs('garbage'), isNull);
      expect(parseThirteenthMonthInputs(const {'year': 2026}), isNull);
    });
  });

  group('13th Month Pay saves write only calculator fields', () {
    test('the document has exactly the four validated fields', () {
      final data = thirteenthMonthDocData(
        monthlySalaries: List<double>.filled(12, 25000),
        otherBenefits: 0,
        year: 2026,
      );
      expect(data.keys.toSet(), {
        'year',
        'monthlyBasicSalaries',
        'otherBenefits',
        'updatedAt',
      });
      expect(data['year'], isA<int>());
      expect(data['monthlyBasicSalaries'], hasLength(12));
      expect(data['updatedAt'], isA<FieldValue>());
      expect(data.containsKey('planner'), isFalse);
    });

    test('a wrong number of salaries is refused before writing', () {
      expect(
        () => thirteenthMonthDocData(
          monthlySalaries: const [1, 2, 3],
          otherBenefits: 0,
          year: 2026,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Budget Planner writes never touch 13th Month Pay data', () {
    final plan = BudgetPlan(
      id: 'plan-1',
      period: PlannerPeriod.day,
      start: DateTime(2026, 11, 12),
      endExclusive: DateTime(2026, 11, 14),
      amounts: const {FinancialCategory.bills: 900},
      createdAt: DateTime(2026, 11, 11, 9),
      alertEligible: true,
      endDate: DateTime(2026, 11, 13),
    );

    test('a plan save writes only plan fields', () {
      final saved = plan.toFirestore();
      expect(saved.containsKey('thirteenthMonth'), isFalse);
      expect(saved.keys.toSet(), plannerPlanFields.toSet());
    });

    test('deleting a plan keeps a damaged legacy calculator record', () {
      final update = plannerDeleteUpdate({
        'id': 'plan-1',
        'period': 'day',
        'thirteenthMonth': _damagedLegacy,
      });
      expect(update.keys.toSet(), {
        for (final field in plannerPlanFields) 'planner.$field',
      });
      expect(update.keys.any((key) => key.contains('thirteenthMonth')), isFalse);
      expect(update.containsKey('planner'), isFalse);
    });

    test('deleting a plan with no calculator data removes the planner field', () {
      final update = plannerDeleteUpdate({'id': 'plan-1', 'period': 'day'});
      expect(update.keys, ['planner']);
      expect(plannerDeleteUpdate(null).keys, ['planner']);
    });
  });

  group('the two features work independently', () {
    late BudgetProvider budget;

    setUp(() {
      budget = BudgetProvider(_StubService(), financeApi: _StubApi());
    });

    tearDown(() => budget.dispose());

    test('the calculator loads zeros when its data is absent', () async {
      final store = _FakeCalculatorStore();
      final calculator = ThirteenthMonthProvider(store, budget);
      addTearDown(calculator.dispose);

      await calculator.loadForUser('user-1');

      expect(calculator.monthlySalaries, List<double>.filled(12, 0));
      expect(calculator.otherBenefits, 0);
      expect(calculator.errorMessage, isNull);
    });

    test('the calculator loads saved inputs from its own store', () async {
      final store = _FakeCalculatorStore(
        stored: parseThirteenthMonthInputs(_completeLegacy),
      );
      final calculator = ThirteenthMonthProvider(store, budget);
      addTearDown(calculator.dispose);

      await calculator.loadForUser('user-1');

      expect(calculator.monthlySalaries, List<double>.filled(12, 24500));
      expect(calculator.otherBenefits, 1500);
    });

    test('the calculator saves only through its own store', () async {
      final store = _FakeCalculatorStore();
      final calculator = ThirteenthMonthProvider(store, budget);
      addTearDown(calculator.dispose);
      await calculator.loadForUser('user-1');

      calculator.fillAllMonths(30000);
      await calculator.saveNow();

      expect(store.saves.single, List<double>.filled(12, 30000));
    });

    test('a failed calculator save reports only a calculator error', () async {
      final store = _FakeCalculatorStore(failSave: true);
      final calculator = ThirteenthMonthProvider(store, budget);
      addTearDown(calculator.dispose);
      await calculator.loadForUser('user-1');

      calculator.fillAllMonths(30000);
      await expectLater(calculator.saveNow(), throwsStateError);

      expect(calculator.errorMessage, 'Salary inputs could not be saved.');
      expect(budget.errorMessage, isNull);
    });
  });

  group('Firestore rules keep the features separate', () {
    final rules = File('firestore.rules').readAsStringSync();

    String body(String function) {
      final start = rules.indexOf('function $function(');
      expect(start, isNonNegative, reason: '$function not found');
      final end = rules.indexOf('\n    }', start);
      return rules.substring(start, end);
    }

    test('planner validation does not validate 13th Month Pay fields', () {
      final planner = body('isValidPlanner');
      expect(planner.contains('isValidThirteenthMonth'), isFalse);
      expect(planner.contains('legacyThirteenthMonthAllowed'), isTrue);
      expect(body('isValidBudgetPlan').contains('isValidThirteenthMonth'), isFalse);
    });

    test('an unchanged legacy copy is accepted without revalidation', () {
      final allowed = body('legacyThirteenthMonthAllowed');
      // Unchanged is checked before full validation, so a damaged but
      // untouched copy never blocks a plan save.
      expect(
        allowed.indexOf('legacyThirteenthMonthUnchanged(planner)'),
        lessThan(allowed.indexOf('isValidThirteenthMonth(')),
      );
      expect(
        body('legacyThirteenthMonthUnchanged').contains(
          'planner.thirteenthMonth == resource.data.planner.thirteenthMonth',
        ),
        isTrue,
      );
    });

    test('the calculator document validates only calculator fields', () {
      final match = rules.indexOf('match /calculators/{docId}');
      expect(match, isNonNegative);
      final block = rules.substring(match, rules.indexOf('\n      }', match));
      expect(block.contains("docId == 'thirteenthMonth'"), isTrue);
      expect(
        block.contains('isValidThirteenthMonth(request.resource.data)'),
        isTrue,
      );
      expect(block.contains('isValidPlanner'), isFalse);
      expect(block.contains('allow delete: if false'), isTrue);
    });
  });
}
