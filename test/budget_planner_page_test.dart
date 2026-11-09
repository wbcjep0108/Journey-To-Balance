import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:just_budget/models/app_currency.dart';
import 'package:just_budget/models/budget_plan.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/providers/budget_provider.dart';
import 'package:just_budget/providers/currency_provider.dart';
import 'package:just_budget/providers/planner_provider.dart';
import 'package:just_budget/screens/home/budget_planner_page.dart';
import 'package:just_budget/services/finance_api_service.dart';
import 'package:just_budget/services/firestore_finance_service.dart';
import 'package:provider/provider.dart';

class _SavedCall {
  const _SavedCall(this.period, this.start, this.endDate);

  final PlannerPeriod period;
  final DateTime start;
  final DateTime? endDate;
}

class _FakePlanner extends ChangeNotifier implements PlannerProvider {
  BudgetPlan? existing;
  final List<_SavedCall> saved = [];

  @override
  BudgetPlan? get plan => existing;

  @override
  bool get hasPlan => existing != null;

  @override
  bool get isSaving => false;

  @override
  bool get isDeleting => false;

  @override
  bool get notificationsEnabled => true;

  @override
  Future<void> savePlan({
    required PlannerPeriod period,
    required DateTime start,
    required Set<FinancialCategory> enabled,
    required Map<FinancialCategory, double> amounts,
    DateTime? endDate,
  }) async {
    saved.add(_SavedCall(period, start, endDate));
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

class _EmptyBudget extends BudgetProvider {
  _EmptyBudget() : super(_StubService(), financeApi: _StubApi());

  static const remaining = {
    FinancialCategory.bills: 12500.0,
    FinancialCategory.savings: 3200.5,
    FinancialCategory.personal: 987654.25,
  };

  @override
  double remainingFor(FinancialCategory category) => remaining[category]!;

  @override
  Future<Map<FinancialCategory, List<FinancialEntry>>> loadEntriesInRange({
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) async => {for (final category in FinancialCategory.values) category: []};
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

DateTime _tomorrow() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day + 1);
}

DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

Future<_FakePlanner> _pumpPage(
  WidgetTester tester, {
  BudgetPlan? existing,
  double textScale = 1,
  Size size = const Size(360, 1700),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final planner = _FakePlanner()..existing = existing;
  final budget = _EmptyBudget();
  addTearDown(budget.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlannerProvider>.value(value: planner),
        ChangeNotifierProvider<BudgetProvider>.value(value: budget),
        ChangeNotifierProvider<CurrencyProvider>.value(
          value: _PlainCurrency(),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const BudgetPlannerPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return planner;
}

Future<void> _enableBills(WidgetTester tester, {String amount = '900'}) async {
  await tester.ensureVisible(find.byType(Switch).first);
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Switch).first);
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey('planner_amount_bills')),
    amount,
  );
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  // A snackbar from an earlier save sits over the Save button.
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .hideCurrentSnackBar();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Save plan'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Save plan'));
  await tester.pumpAndSettle();
}

Future<void> _tapChipText(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> _tapChip(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

/// Opens the date picker behind [pillKey], types [date], and presses OK.
/// Returns true when the dialog closed.
Future<bool> _typeDate(
  WidgetTester tester,
  String pillKey,
  DateTime date,
) async {
  await tester.ensureVisible(find.byKey(ValueKey(pillKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(pillKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(DatePickerDialog),
      matching: find.byType(TextField),
    ),
    DateFormat('MM/dd/yyyy').format(date),
  );
  await tester.pump();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
  return find.byType(DatePickerDialog).evaluate().isEmpty;
}

Finder _untilText(DateTime date) =>
    find.text('Until ${plannerFriendlyDate(date)}');

void main() {
  testWidgets('Day with no Until behaves like a one-day plan', (tester) async {
    final planner = await _pumpPage(tester);
    final tomorrow = _tomorrow();

    expect(find.byKey(const ValueKey('planner-until-date')), findsOneWidget);
    expect(_untilText(tomorrow), findsOneWidget);

    await _enableBills(tester);
    await _tapSave(tester);

    expect(planner.saved, hasLength(1));
    expect(planner.saved.single.period, PlannerPeriod.day);
    expect(planner.saved.single.start, tomorrow);
    expect(planner.saved.single.endDate, isNull);
    expect(find.byKey(const ValueKey('planner-per-day')), findsNothing);
  });

  testWidgets('quick chips set Until to start plus N minus 1 days', (
    tester,
  ) async {
    final planner = await _pumpPage(tester);
    final tomorrow = _tomorrow();
    await _enableBills(tester);

    for (final days in [2, 3, 5]) {
      await _tapChip(tester, 'planner-days-$days');
      expect(_untilText(_addDays(tomorrow, days - 1)), findsOneWidget);
      await _tapSave(tester);
      expect(planner.saved.last.endDate, _addDays(tomorrow, days - 1));
    }

    await _tapChip(tester, 'planner-days-1');
    expect(_untilText(tomorrow), findsOneWidget);
    await _tapSave(tester);
    expect(planner.saved.last.endDate, isNull);
  });

  testWidgets('changing the start date keeps the range length', (tester) async {
    final planner = await _pumpPage(tester);
    await _enableBills(tester);
    await _tapChip(tester, 'planner-days-3');

    final newStart = _addDays(DateTime.now(), 9);
    final closed = await _typeDate(tester, 'planner-start-date', newStart);
    expect(closed, isTrue);

    expect(_untilText(_addDays(newStart, 2)), findsOneWidget);
    await _tapSave(tester);
    expect(planner.saved.last.start, DateUtils.dateOnly(newStart));
    expect(planner.saved.last.endDate, _addDays(newStart, 2));
  });

  testWidgets('the Until picker rejects a date before the start', (
    tester,
  ) async {
    await _pumpPage(tester);
    final closed = await _typeDate(
      tester,
      'planner-until-date',
      _addDays(_tomorrow(), -1),
    );
    expect(closed, isFalse);
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('the Until picker rejects a Day range longer than six days', (
    tester,
  ) async {
    final planner = await _pumpPage(tester);
    final tomorrow = _tomorrow();
    await _enableBills(tester);

    // Seven days in total is a Week, so it is refused.
    final tooLong = await _typeDate(
      tester,
      'planner-until-date',
      _addDays(tomorrow, 6),
    );
    expect(tooLong, isFalse);
    expect(find.byType(DatePickerDialog), findsOneWidget);

    // Six days in total is the longest Day range and is accepted.
    await tester.enterText(
      find.descendant(
        of: find.byType(DatePickerDialog),
        matching: find.byType(TextField),
      ),
      DateFormat('MM/dd/yyyy').format(_addDays(tomorrow, 5)),
    );
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(_untilText(_addDays(tomorrow, 5)), findsOneWidget);

    await _tapSave(tester);
    expect(planner.saved.last.endDate, _addDays(tomorrow, 5));
  });

  testWidgets('switching modes clears Until and Day restores one day', (
    tester,
  ) async {
    final planner = await _pumpPage(tester);
    final tomorrow = _tomorrow();
    await _enableBills(tester);
    await _tapChip(tester, 'planner-days-3');

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-until-date')), findsNothing);
    expect(
      find.text('One budget for 7 days from your start date.'),
      findsOneWidget,
    );
    await _tapSave(tester);
    expect(planner.saved.last.period, PlannerPeriod.week);
    expect(planner.saved.last.endDate, isNull);

    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-until-date')), findsNothing);
    expect(
      find.text(
        'One budget from your start date to the day before the same date '
        'next month.',
      ),
      findsOneWidget,
    );
    await _tapSave(tester);
    expect(planner.saved.last.period, PlannerPeriod.month);
    expect(planner.saved.last.endDate, isNull);

    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('planner-until-date')), findsOneWidget);
    expect(_untilText(tomorrow), findsOneWidget);
    expect(
      find.text(
        'One budget for the days you choose. Pick an end date to cover up '
        'to 6 days.',
      ),
      findsOneWidget,
    );
    await _tapSave(tester);
    expect(planner.saved.last.period, PlannerPeriod.day);
    expect(planner.saved.last.endDate, isNull);
  });

  testWidgets('the hero card shows the range and the per-day amount', (
    tester,
  ) async {
    await _pumpPage(tester);
    await _enableBills(tester, amount: '900');
    await _tapChip(tester, 'planner-days-3');

    final tomorrow = _tomorrow();
    final first = DateFormat('MMM d').format(tomorrow);
    final last = DateFormat('MMM d').format(_addDays(tomorrow, 2));

    expect(find.text('Starts $first'), findsOneWidget);
    expect(find.text('$first - $last - 3-day plan'), findsOneWidget);
    expect(find.text('About PHP 300.00 per day'), findsOneWidget);
    expect(find.text('BUDGET PLAN'), findsOneWidget);
  });

  testWidgets('a saved multi-day plan opens with its range selected', (
    tester,
  ) async {
    final start = DateTime(2026, 10, 28);
    final saved = BudgetPlan(
      id: 'saved',
      period: PlannerPeriod.day,
      start: start,
      endExclusive: DateTime(2026, 10, 31),
      amounts: const {FinancialCategory.bills: 600},
      createdAt: start,
      alertEligible: true,
      endDate: DateTime(2026, 10, 30),
    );
    await _pumpPage(tester, existing: saved);

    expect(_untilText(DateTime(2026, 10, 30)), findsOneWidget);
    expect(find.text('Preview - not saved yet'), findsNothing);

    // Changing only the range marks the draft as unsaved.
    await _tapChip(tester, 'planner-days-2');
    expect(find.text('Preview - not saved yet'), findsOneWidget);
  });

  testWidgets('each category shows how much money it has left', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpPage(tester);

    expect(find.text('PHP 12500.00'), findsOneWidget);
    expect(find.text('PHP 3200.50'), findsOneWidget);
    expect(find.text('PHP 987654.25'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Bills, PHP 12500.00 available'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the info button explains all three periods', (tester) async {
    await _pumpPage(tester);

    await tester.tap(find.byTooltip('About budget periods'));
    await tester.pumpAndSettle();

    expect(find.text('Budget periods'), findsOneWidget);
    expect(
      find.text('Example: Oct 28 to Oct 30 is one budget that covers 3 days.'),
      findsOneWidget,
    );
    expect(
      find.text('Example: starting Oct 28 covers Oct 28 to Nov 3.'),
      findsOneWidget,
    );
    expect(
      find.text('Example: starting Oct 28 covers Oct 28 to Nov 27.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Budget periods'), findsNothing);
  });

  testWidgets('Until, chips, and info button have semantics labels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpPage(tester);

    expect(find.bySemanticsLabel(RegExp('^Until date')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Start date')), findsOneWidget);
    expect(find.bySemanticsLabel('Cover 3 days'), findsOneWidget);
    expect(find.bySemanticsLabel('Cover 1 day'), findsOneWidget);
    expect(find.bySemanticsLabel('About budget periods'), findsOneWidget);
    handle.dispose();
  });

  for (final period in PlannerPeriod.values) {
    testWidgets('no overflow at 1.3x text on 360 px in ${period.label}', (
      tester,
    ) async {
      await _pumpPage(tester, textScale: 1.3, size: const Size(360, 740));
      await _enableBills(tester, amount: '900');
      if (period != PlannerPeriod.day) {
        await _tapChipText(tester, period.label);
      } else {
        await _tapChip(tester, 'planner-days-5');
      }
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byTooltip('About budget periods'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('About budget periods'));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
