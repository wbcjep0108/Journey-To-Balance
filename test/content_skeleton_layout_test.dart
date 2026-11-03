import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/screens/legal/legal_acceptance_gate.dart';
import 'package:just_budget/screens/onboarding/onboarding_screen.dart';
import 'package:just_budget/widgets/foreign_exchange_card.dart';

Widget _app(Widget child) {
  return MaterialApp(
    builder: (context, appChild) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: const TextScaler.linear(1.3),
      ),
      child: appChild!,
    ),
    home: child,
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .views
            .first
            .devicePixelRatio =
        1;
    TestWidgetsFlutterBinding
        .instance
        .platformDispatcher
        .views
        .first
        .physicalSize = const Size(
      360,
      800,
    );
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetDevicePixelRatio();
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetPhysicalSize();
  });

  testWidgets('foreign exchange skeleton preserves three 48px rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(20),
            child: ForeignExchangeCardSkeleton(),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('foreign-exchange-skeleton'))),
      const Size(320, 168),
    );
    for (var index = 0; index < 3; index++) {
      expect(
        tester
            .getSize(
              find.byKey(ValueKey('foreign-exchange-skeleton-row-$index')),
            )
            .height,
        48,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('legal skeleton preserves checkbox and button heights', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const LegalAcceptanceSkeleton()));

    expect(
      tester
          .getSize(find.byKey(const ValueKey('legal-skeleton-checkbox-row')))
          .height,
      48,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('legal-skeleton-button')))
          .height,
      52,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding skeleton preserves slide control dimensions', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const OnboardingPageSkeleton()));

    expect(
      tester.getSize(find.byKey(const ValueKey('onboarding-skeleton-badge'))),
      const Size(56, 56),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('onboarding-skeleton-field')))
          .height,
      56,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('onboarding-skeleton-button')))
          .height,
      52,
    );
    expect(tester.takeException(), isNull);
  });
}
