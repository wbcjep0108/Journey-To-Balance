import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:just_budget/screens/auth/pin_setup_screen.dart';
import 'package:just_budget/widgets/security_ui.dart';

void main() {
  testWidgets('PIN mismatch shows an error without ErrorWidget', (tester) async {
    tester.view.physicalSize = const Size(1280, 2772);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    addTearDown(tester.view.reset);

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );

    await tester.pumpWidget(const MaterialApp(home: PinSetupScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(8));

    for (var i = 0; i < 4; i++) {
      await tester.enterText(fields.at(i), '${i + 1}');
      await tester.pump();
    }
    for (var i = 0; i < 4; i++) {
      await tester.enterText(fields.at(4 + i), '${5 + i}');
      await tester.pump();
    }

    final continueBtn = find.widgetWithText(SecurityActionButton, 'Continue');
    tester.widget<SecurityActionButton>(continueBtn).onPressed!.call();
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('PINs do not match. Try again.'), findsOneWidget);
  });
}
