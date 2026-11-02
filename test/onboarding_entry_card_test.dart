import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/screens/home/home_page.dart';

void main() {
  testWidgets('Finish setup card fits at 360px and 1.3x text scale', (
    tester,
  ) async {
    var tapped = false;
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: FinishSetupCard(onTap: () => tapped = true),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Finish setup'), findsOneWidget);
    await tester.tap(find.text('Finish setup'));
    expect(tapped, isTrue);
  });
}
