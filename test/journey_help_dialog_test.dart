import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/widgets/journey_help_dialog.dart';

void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    JourneyHelpDialog(versionLoader: () async => '3.0.0'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('help dialog shows its actions and closes', (tester) async {
    await openDialog(tester);

    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('bcueva1217@gmail.com'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Send email'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.text('Help & Support'), findsNothing);
  });

  testWidgets('copy puts the support address on the clipboard', (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await openDialog(tester);
    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(copiedText, 'bcueva1217@gmail.com');
    expect(find.text('Email copied'), findsOneWidget);
  });

  testWidgets('help dialog does not overflow at 1.3x text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: JourneyHelpDialog(versionLoader: () async => '3.0.0'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Help & Support'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
