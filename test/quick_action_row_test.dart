import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/providers/budget_provider.dart';
import 'package:just_budget/providers/planner_provider.dart';
import 'package:just_budget/screens/home/home_page.dart';
import 'package:provider/provider.dart';

class _FakeBudgetProvider extends ChangeNotifier implements BudgetProvider {
  @override
  double get savingsGoalProgress => 0.5;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlannerProvider extends ChangeNotifier implements PlannerProvider {
  @override
  double get progress => 0.4;

  @override
  bool get hasPlan => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestWidget(double width) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<BudgetProvider>(
          create: (_) => _FakeBudgetProvider(),
        ),
        ChangeNotifierProvider<PlannerProvider>(
          create: (_) => _FakePlannerProvider(),
        ),
      ],
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: const QuickActionRow(),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('QuickActionRow layout and responsiveness at widths 320, 360, and 430', (
    tester,
  ) async {
    // Width 320: cannot fit all 5 buttons (5 * 64 + 4 * 12 + 40 = 408 > 320) -> should be scrollable (ListView)
    await tester.pumpWidget(_buildTestWidget(320));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(Row), findsNothing);

    // Width 360: 408 > 360 -> should also be scrollable (ListView)
    await tester.pumpWidget(_buildTestWidget(360));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(Row), findsNothing);

    // Width 430: 408 <= 430 -> fits, so it should render as a non-scrollable Row with spaceBetween
    await tester.pumpWidget(_buildTestWidget(430));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Row), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });
}

