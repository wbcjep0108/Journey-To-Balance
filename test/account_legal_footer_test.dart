import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/screens/account/account_page.dart';

void main() {
  Future<void> pumpFooter(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 300);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AccountLegalFooter(
              onAbout: () {},
              onTermsOfService: () {},
              onPrivacyPolicy: () {},
            ),
          ),
        ),
      ),
    );
  }

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  for (final width in [320.0, 430.0, 800.0]) {
    testWidgets('legal footer fits a $width logical-pixel viewport', (
      tester,
    ) async {
      await pumpFooter(tester, width: width);

      expect(find.text('About Journey to Balance'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legal footer fits compact screens with larger text', (
    tester,
  ) async {
    await pumpFooter(tester, width: 320, textScale: 1.5);

    expect(tester.takeException(), isNull);
  });
}
