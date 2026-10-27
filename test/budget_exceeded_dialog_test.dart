import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/widgets/budget_exceeded_dialog.dart';

void main() {
  testWidgets(
    'budget exceeded popup shows its summary and closes with Got it',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const BudgetExceededDialog(
                    planLabel: "Today's plan - Oct 27",
                    budgetAmount: 'PHP 1,500',
                    spentAmount: 'PHP 1,750',
                    overAmount: 'PHP 250',
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('You went over budget'), findsOneWidget);
      expect(find.text("Today's plan - Oct 27"), findsOneWidget);
      expect(find.text('PHP 1,500'), findsOneWidget);
      expect(find.text('PHP 1,750'), findsOneWidget);
      expect(find.text('PHP 250'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      final dialog = find.byType(Dialog);
      expect(
        find.descendant(of: dialog, matching: find.byType(IconButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(TextButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(FilledButton)),
        findsOneWidget,
      );

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      expect(find.text('You went over budget'), findsNothing);
    },
  );

  testWidgets('budget exceeded popup fits at 1.3x text scale', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: BudgetExceededDialog(
                  planLabel: "Today's plan - Oct 27",
                  budgetAmount: 'PHP 1,500,000',
                  spentAmount: 'PHP 1,750,000',
                  overAmount: 'PHP 250,000',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('PHP 1,750,000'), findsOneWidget);
  });
}
