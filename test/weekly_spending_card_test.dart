import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/app_currency.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/providers/budget_provider.dart';
import 'package:just_budget/providers/currency_provider.dart';
import 'package:just_budget/services/finance_api_service.dart';
import 'package:just_budget/services/firestore_finance_service.dart';
import 'package:just_budget/widgets/weekly_spending_card.dart';
import 'package:provider/provider.dart';

class _StubService implements FirestoreFinanceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubApi implements FinanceApiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCurrencyProvider extends ChangeNotifier implements CurrencyProvider {
  @override
  AppCurrency get currency => AppCurrency.php;

  @override
  String get symbol => 'PHP';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Real BudgetProvider (so weeklySpendingForEntries is the production code)
/// with the live entry list and the range query under test control.
class _TestBudget extends BudgetProvider {
  _TestBudget() : super(_StubService(), financeApi: _StubApi());

  final Map<FinancialCategory, List<FinancialEntry>> live = {
    for (final category in FinancialCategory.values) category: [],
  };
  Map<FinancialCategory, List<FinancialEntry>> base = {
    for (final category in FinancialCategory.values) category: [],
  };
  final List<DateTime> rangeStarts = [];
  int failNext = 0;

  int get rangeCalls => rangeStarts.length;

  @override
  List<FinancialEntry> entriesFor(FinancialCategory category) =>
      List.unmodifiable(live[category]!);

  @override
  Future<Map<FinancialCategory, List<FinancialEntry>>> loadEntriesInRange({
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) async {
    rangeStarts.add(startInclusive);
    if (failNext > 0) {
      failNext--;
      throw StateError('boom');
    }
    return base;
  }

  void touch() => notifyListeners();
}

DateTime _thisMonday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day - (now.weekday - 1));
}

FinancialEntry _entry(
  String id,
  double amount,
  DateTime at, {
  bool refund = false,
  String title = 'Lunch',
}) => FinancialEntry(
  id: id,
  title: title,
  amount: amount,
  createdAt: at,
  isRefund: refund,
);

Future<void> _pumpCard(
  WidgetTester tester,
  _TestBudget budget, {
  DateTime Function()? clock,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BudgetProvider>.value(value: budget),
        ChangeNotifierProvider<CurrencyProvider>.value(
          value: _FakeCurrencyProvider(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WeeklySpendingCard(
              clock: clock,
              retryDelay: const Duration(milliseconds: 100),
            ),
          ),
        ),
      ),
    ),
  );
  // Let the initial range query resolve and rebuild.
  await tester.pump();
  await tester.pump();
}

/// Amount per weekday label, read from the bar tooltips.
Map<String, double> _spent(WidgetTester tester) {
  final out = <String, double>{};
  for (final tip in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
    final parts = tip.message!.split('\n');
    out[parts[0]] = double.parse(parts[1].replaceAll(RegExp(r'[^0-9.]'), ''));
  }
  return out;
}

const _retryText = 'Couldn\'t refresh. Tap to retry.';

void main() {
  group('mergeWeekEntries', () {
    final weekStart = DateTime(2026, 11, 2);
    final weekEnd = DateTime(2026, 11, 9);
    final monday = DateTime(2026, 11, 2, 9);

    Map<FinancialCategory, List<FinancialEntry>> only(
      List<FinancialEntry> bills,
    ) => {
      for (final category in FinancialCategory.values)
        category: category == FinancialCategory.bills ? bills : [],
    };

    test('a short live list is complete, so unlisted base entries are gone', () {
      final merged = mergeWeekEntries(
        base: only([_entry('a', 10, monday), _entry('b', 20, monday)]),
        live: only([_entry('a', 10, monday)]),
        weekStart: weekStart,
        weekEnd: weekEnd,
        livePageSize: 50,
      );
      expect(merged[FinancialCategory.bills]!.map((e) => e.id), ['a']);
    });

    test('the live copy wins when an id exists on both sides', () {
      final merged = mergeWeekEntries(
        base: only([_entry('a', 100, monday)]),
        live: only([_entry('a', 40, monday)]),
        weekStart: weekStart,
        weekEnd: weekEnd,
        livePageSize: 50,
      );
      final entries = merged[FinancialCategory.bills]!;
      expect(entries.length, 1);
      expect(entries.single.amount, 40);
    });

    test('a full live list keeps older base entries and drops newer gaps', () {
      final live = [
        for (var i = 10; i < 60; i++)
          _entry('e$i', 1, monday.add(Duration(minutes: i))),
      ];
      final merged = mergeWeekEntries(
        base: only([
          for (var i = 0; i < 60; i++)
            _entry('e$i', 1, monday.add(Duration(minutes: i))),
          _entry('gone', 1, monday.add(const Duration(minutes: 30))),
        ]),
        live: only(live),
        weekStart: weekStart,
        weekEnd: weekEnd,
        livePageSize: 50,
      );
      final ids = merged[FinancialCategory.bills]!.map((e) => e.id).toSet();
      expect(ids.length, 60);
      expect(ids.contains('gone'), isFalse);
      expect(ids.contains('e0'), isTrue);
    });

    test('entries outside the week are ignored', () {
      final merged = mergeWeekEntries(
        base: only([_entry('old', 5, DateTime(2026, 10, 30))]),
        live: only([_entry('next', 5, DateTime(2026, 11, 9, 1))]),
        weekStart: weekStart,
        weekEnd: weekEnd,
        livePageSize: 50,
      );
      expect(merged[FinancialCategory.bills], isEmpty);
    });
  });

  group('WeeklySpendingCard', () {
    testWidgets('a new transaction appears immediately without a query', (
      tester,
    ) async {
      final budget = _TestBudget();
      addTearDown(budget.dispose);
      await _pumpCard(tester, budget);
      expect(_spent(tester)['Monday'], 0);
      expect(budget.rangeCalls, 1);

      budget.live[FinancialCategory.personal] = [
        _entry('new', 125, _thisMonday().add(const Duration(hours: 1))),
      ];
      budget.touch();
      await tester.pump();

      expect(_spent(tester)['Monday'], 125);
      expect(budget.rangeCalls, 1);
    });

    testWidgets('delete removes the transaction from the bar', (tester) async {
      final monday = _thisMonday();
      final a = _entry('a', 100, monday.add(const Duration(hours: 1)));
      final b = _entry('b', 50, monday.add(const Duration(hours: 2)));
      final budget = _TestBudget()
        ..base[FinancialCategory.bills] = [a, b]
        ..live[FinancialCategory.bills] = [a, b];
      addTearDown(budget.dispose);
      await _pumpCard(tester, budget);
      expect(_spent(tester)['Monday'], 150);

      budget.live[FinancialCategory.bills] = [b];
      budget.touch();
      await tester.pump();

      expect(_spent(tester)['Monday'], 50);
      expect(budget.rangeCalls, 1);
    });

    testWidgets('undoing a savings contribution removes it from the bar', (
      tester,
    ) async {
      final monday = _thisMonday();
      final goal = _entry(
        'goal',
        300,
        monday.add(const Duration(days: 1, hours: 1)),
        title: BudgetProvider.savingsGoalEntryTitle,
      );
      final budget = _TestBudget()
        ..base[FinancialCategory.savings] = [goal]
        ..live[FinancialCategory.savings] = [goal];
      addTearDown(budget.dispose);
      await _pumpCard(tester, budget);
      expect(_spent(tester)['Tuesday'], 300);

      budget.live[FinancialCategory.savings] = [];
      budget.touch();
      await tester.pump();

      expect(_spent(tester)['Tuesday'], 0);
    });

    testWidgets('a refund removes the transaction from the bar', (tester) async {
      final monday = _thisMonday();
      final a = _entry('a', 80, monday.add(const Duration(hours: 1)));
      final budget = _TestBudget()
        ..base[FinancialCategory.personal] = [a]
        ..live[FinancialCategory.personal] = [a];
      addTearDown(budget.dispose);
      await _pumpCard(tester, budget);
      expect(_spent(tester)['Monday'], 80);

      budget.live[FinancialCategory.personal] = [a.copyWith(isRefund: true)];
      budget.touch();
      await tester.pump();

      expect(_spent(tester)['Monday'], 0);
    });

    testWidgets('a week with more than 50 entries in one category stays right', (
      tester,
    ) async {
      final monday = _thisMonday();
      FinancialEntry e(int i) =>
          _entry('e$i', 10, monday.add(Duration(minutes: i)));

      // 70 entries in the week. The live window holds only the newest 50.
      final budget = _TestBudget()
        ..base[FinancialCategory.bills] = [for (var i = 0; i < 70; i++) e(i)]
        ..live[FinancialCategory.bills] = [
          for (var i = 69; i >= 20; i--) e(i),
        ];
      addTearDown(budget.dispose);
      await _pumpCard(tester, budget);
      expect(_spent(tester)['Monday'], 700);

      // A new entry pushes the oldest live entry out of the window. It is
      // still counted through the base snapshot.
      budget.live[FinancialCategory.bills] = [
        for (var i = 70; i >= 21; i--) e(i),
      ];
      budget.touch();
      await tester.pump();
      expect(_spent(tester)['Monday'], 710);

      // Delete e40. The live snapshot refills to 50 by pulling e20 back in.
      budget.live[FinancialCategory.bills] = [
        for (var i = 70; i >= 21; i--)
          if (i != 40) e(i),
        e(20),
      ];
      budget.touch();
      await tester.pump();
      expect(_spent(tester)['Monday'], 700);
      expect(budget.rangeCalls, 1);
    });

    testWidgets('no range query runs per provider change', (tester) async {
      final budget = _TestBudget();
      addTearDown(budget.dispose);
      await _pumpCard(tester, budget);

      for (var i = 0; i < 5; i++) {
        budget.live[FinancialCategory.bills] = [
          _entry('x$i', 1, _thisMonday().add(Duration(hours: i + 1))),
        ];
        budget.touch();
        await tester.pump();
      }

      expect(budget.rangeCalls, 1);
    });

    testWidgets('the midnight check reloads when the week rolls over', (
      tester,
    ) async {
      final budget = _TestBudget();
      addTearDown(budget.dispose);
      // Sunday 8 Nov 2026, thirty seconds before midnight.
      var fakeNow = DateTime(2026, 11, 8, 23, 59, 30);
      await _pumpCard(tester, budget, clock: () => fakeNow);
      expect(budget.rangeStarts, [DateTime(2026, 11, 2)]);

      fakeNow = DateTime(2026, 11, 9, 0, 0, 5);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(budget.rangeStarts, [DateTime(2026, 11, 2), DateTime(2026, 11, 9)]);
    });

    testWidgets('the midnight check does not reload within the same week', (
      tester,
    ) async {
      final budget = _TestBudget();
      addTearDown(budget.dispose);
      // Wednesday 4 Nov 2026, thirty seconds before midnight.
      var fakeNow = DateTime(2026, 11, 4, 23, 59, 30);
      await _pumpCard(tester, budget, clock: () => fakeNow);

      fakeNow = DateTime(2026, 11, 5, 0, 0, 5);
      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(budget.rangeCalls, 1);
    });

    testWidgets('resuming the app refetches, and picks up a new week', (
      tester,
    ) async {
      final budget = _TestBudget();
      addTearDown(budget.dispose);
      var fakeNow = DateTime(2026, 11, 4, 12);
      await _pumpCard(tester, budget, clock: () => fakeNow);
      expect(budget.rangeStarts, [DateTime(2026, 11, 2)]);

      // Same week: still refetches the base snapshot.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(budget.rangeStarts, [DateTime(2026, 11, 2), DateTime(2026, 11, 2)]);

      // Next week: the refetch targets the new Monday.
      fakeNow = DateTime(2026, 11, 10, 9);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(budget.rangeStarts.last, DateTime(2026, 11, 9));
      expect(budget.rangeCalls, 3);
    });

    testWidgets('a failed first load retries once automatically', (
      tester,
    ) async {
      final budget = _TestBudget()..failNext = 1;
      addTearDown(budget.dispose);
      await _pumpCard(tester, budget);
      expect(budget.rangeCalls, 1);

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(budget.rangeCalls, 2);
      expect(find.text(_retryText), findsNothing);
    });

    testWidgets('two failures show a quiet tap-to-retry state', (tester) async {
      final budget = _TestBudget()..failNext = 2;
      addTearDown(budget.dispose);
      await _pumpCard(tester, budget);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(budget.rangeCalls, 2);
      expect(find.text(_retryText), findsOneWidget);
      // No raw error text reaches the user.
      expect(find.textContaining('boom'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      // The bars still render from live data while the base is unavailable.
      expect(_spent(tester).length, 7);

      await tester.tap(find.text(_retryText));
      await tester.pump();
      await tester.pump();

      expect(budget.rangeCalls, 3);
      expect(find.text(_retryText), findsNothing);
    });
  });
}
