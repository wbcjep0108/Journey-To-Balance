import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/providers/budget_provider.dart';
import 'package:just_budget/providers/thirteenth_month_provider.dart';
import 'package:just_budget/screens/home/thirteenth_month_screen.dart';
import 'package:just_budget/services/finance_api_service.dart';
import 'package:just_budget/services/firestore_finance_service.dart';
import 'package:just_budget/services/thirteenth_month_firestore_service.dart';
import 'package:provider/provider.dart';

class _StubService implements FirestoreFinanceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubApi implements FinanceApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Calculator storage whose next loads can be made to fail.
class _FlakyStore implements ThirteenthMonthFirestoreService {
  _FlakyStore({this.stored, List<Object> failures = const []})
    : _failures = [...failures];

  ThirteenthMonthInputs? stored;
  final List<Object> _failures;
  int loads = 0;
  final List<List<double>> saves = [];

  void failNext(Object error) => _failures.add(error);

  @override
  Future<ThirteenthMonthInputs?> load(String uid) async {
    loads++;
    if (_failures.isNotEmpty) throw _failures.removeAt(0);
    return stored;
  }

  @override
  Future<void> save(
    String uid, {
    required List<double> monthlySalaries,
    required double otherBenefits,
  }) async {
    saves.add(List<double>.from(monthlySalaries));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _offline = FirebaseException(
  plugin: 'cloud_firestore',
  code: 'unavailable',
  message: 'Failed to get document because the client is offline.',
);

const _saved = ThirteenthMonthInputs(
  monthlySalaries: [
    25000, 25000, 25000, 25000, 25000, 25000,
    25000, 25000, 25000, 25000, 25000, 25000,
  ],
  otherBenefits: 1200,
);

void main() {
  late BudgetProvider budget;

  setUp(() => budget = BudgetProvider(_StubService(), financeApi: _StubApi()));
  tearDown(() => budget.dispose());

  ThirteenthMonthProvider calculatorFor(_FlakyStore store) {
    final calculator = ThirteenthMonthProvider(store, budget);
    addTearDown(calculator.dispose);
    return calculator;
  }

  group('session start', () {
    test('an offline calculator load does not stop the session', () async {
      final store = _FlakyStore(stored: _saved, failures: [_offline]);
      final calculator = calculatorFor(store);

      // Must complete without throwing, so the rest of startup continues.
      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      expect(calculator.loadFailed, isTrue);
      expect(calculator.hasLoaded, isFalse);
      expect(calculator.errorMessage, ThirteenthMonthProvider.loadErrorMessage);
      expect(budget.errorMessage, isNull);
    });

    test('any other calculator load failure does not stop the session', () async {
      final store = _FlakyStore(failures: [StateError('permission-denied')]);
      final calculator = calculatorFor(store);

      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      expect(calculator.loadFailed, isTrue);
      expect(budget.errorMessage, isNull);
    });

    test('a successful load is unchanged', () async {
      final store = _FlakyStore(stored: _saved);
      final calculator = calculatorFor(store);

      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      expect(calculator.hasLoaded, isTrue);
      expect(calculator.loadFailed, isFalse);
      expect(calculator.monthlySalaries, _saved.monthlySalaries);
      expect(calculator.otherBenefits, 1200);
      expect(calculator.errorMessage, isNull);
    });
  });

  group('after a failed load', () {
    test('edits and saves are blocked so stored data is not overwritten', () async {
      final store = _FlakyStore(stored: _saved, failures: [_offline]);
      final calculator = calculatorFor(store);
      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      calculator.setMonthlySalary(0, 99999);
      calculator.fillAllMonths(1);
      calculator.setOtherBenefits(5);
      await calculator.saveNow();
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(store.saves, isEmpty);
      expect(calculator.monthlySalaries, List<double>.filled(12, 0));
      expect(calculator.errorMessage, ThirteenthMonthProvider.loadErrorMessage);
    });

    test('retry loads the saved data and unblocks saving', () async {
      final store = _FlakyStore(stored: _saved, failures: [_offline]);
      final calculator = calculatorFor(store);
      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      expect(await calculator.retryLoad(), isTrue);

      expect(calculator.hasLoaded, isTrue);
      expect(calculator.loadFailed, isFalse);
      expect(calculator.errorMessage, isNull);
      expect(calculator.monthlySalaries, _saved.monthlySalaries);

      calculator.setMonthlySalary(0, 30000);
      await calculator.saveNow();
      expect(store.saves.single.first, 30000);
      expect(store.saves.single.skip(1), everyElement(25000));
    });

    test('a retry that fails again keeps saves blocked', () async {
      final store = _FlakyStore(failures: [_offline, _offline]);
      final calculator = calculatorFor(store);
      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      expect(await calculator.retryLoad(), isFalse);

      expect(calculator.loadFailed, isTrue);
      calculator.fillAllMonths(1000);
      await calculator.saveNow();
      expect(store.saves, isEmpty);
    });

    test('the session retry path loads the calculator again', () async {
      final store = _FlakyStore(stored: _saved, failures: [_offline]);
      final calculator = calculatorFor(store);
      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      // The app's "retry" reruns session loading for the same user.
      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      expect(store.loads, 2);
      expect(calculator.hasLoaded, isTrue);
    });

    test('a loaded user is not reloaded on later session loads', () async {
      final store = _FlakyStore(stored: _saved);
      final calculator = calculatorFor(store);
      await loadCalculatorWithoutBlocking(calculator, 'user-1');
      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      expect(store.loads, 1);
    });

    test('signing out clears the failed state', () async {
      final store = _FlakyStore(failures: [_offline]);
      final calculator = calculatorFor(store);
      await loadCalculatorWithoutBlocking(calculator, 'user-1');

      await calculator.clear();

      expect(calculator.loadFailed, isFalse);
      expect(calculator.hasLoaded, isFalse);
      expect(calculator.errorMessage, isNull);
    });
  });

  group('13th Month Pay screen', () {
    Future<ThirteenthMonthProvider> pumpScreen(
      WidgetTester tester,
      _FlakyStore store,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 2400);
      addTearDown(tester.view.reset);
      final calculator = ThirteenthMonthProvider(store, budget);
      addTearDown(calculator.dispose);
      await loadCalculatorWithoutBlocking(calculator, 'user-1');
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<BudgetProvider>.value(value: budget),
            ChangeNotifierProvider<ThirteenthMonthProvider>.value(
              value: calculator,
            ),
          ],
          child: const MaterialApp(home: ThirteenthMonthScreen()),
        ),
      );
      await tester.pump();
      return calculator;
    }

    testWidgets('shows the load error with Retry and read-only inputs', (
      tester,
    ) async {
      final store = _FlakyStore(stored: _saved, failures: [_offline]);
      await pumpScreen(tester, store);

      expect(
        find.byKey(const ValueKey('thirteenth-month-error')),
        findsOneWidget,
      );
      expect(find.text(ThirteenthMonthProvider.loadErrorMessage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('thirteenth-month-retry')),
        findsOneWidget,
      );
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields, isNotEmpty);
      expect(fields.every((field) => field.enabled == false), isTrue);
      expect(
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Fill'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('Retry loads the saved inputs into the fields', (tester) async {
      final store = _FlakyStore(stored: _saved, failures: [_offline]);
      final calculator = await pumpScreen(tester, store);

      await tester.tap(find.byKey(const ValueKey('thirteenth-month-retry')));
      await tester.pumpAndSettle();

      expect(calculator.hasLoaded, isTrue);
      expect(find.byKey(const ValueKey('thirteenth-month-error')), findsNothing);
      expect(find.byKey(const ValueKey('thirteenth-month-retry')), findsNothing);
      expect(find.text('25000'), findsNWidgets(12));
      expect(find.text('1200'), findsOneWidget);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.every((field) => field.enabled != false), isTrue);
    });

    testWidgets('a loaded calculator shows no error and editable inputs', (
      tester,
    ) async {
      await pumpScreen(tester, _FlakyStore(stored: _saved));

      expect(find.byKey(const ValueKey('thirteenth-month-error')), findsNothing);
      expect(find.byKey(const ValueKey('thirteenth-month-retry')), findsNothing);
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.every((field) => field.enabled != false), isTrue);
    });
  });
}
