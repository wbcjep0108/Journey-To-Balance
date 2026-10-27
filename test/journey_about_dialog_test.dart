import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/widgets/journey_about_dialog.dart';

void main() {
  testWidgets('about dialog shows content and closes from its only button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const JourneyAboutDialog(version: '3.0.0'),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('About Journey to Balance'), findsOneWidget);
    expect(find.text('Version 3.0.0'), findsOneWidget);
    expect(find.text('Track income and expenses'), findsOneWidget);
    expect(find.text('Manage your bills'), findsOneWidget);
    expect(find.text('Monitor your savings'), findsOneWidget);
    expect(find.text('Sync securely across your devices'), findsOneWidget);
    expect(find.text('DEVELOPER'), findsOneWidget);
    expect(find.text('Wilhem Bruce Cuevas'), findsOneWidget);
    expect(find.text('BSIT student, National University Manila'), findsOneWidget);

    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.byType(FilledButton)),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('About Journey to Balance'), findsNothing);
  });

  testWidgets('about dialog does not overflow at 1.3x on a 360 wide screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: JourneyAboutDialog(version: '3.0.0'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('About Journey to Balance'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
