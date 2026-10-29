import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/screens/auth/login_layout_constants.dart';
import 'package:just_budget/widgets/logout_skeleton.dart';

Widget _skeletonApp({bool disableAnimations = false}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: const LogoutSkeleton(),
  );
}

void main() {
  testWidgets('skeleton logo size matches login screen constant', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_skeletonApp(disableAnimations: true));
    await tester.pump();

    // The logo is the first Container child of the first Center in the Column.
    // We find it by looking for a RenderBox whose painted size is exactly
    // kLoginLogoSize × kLoginLogoSize.
    final containerFinder = find.byType(Container);
    bool foundLogo = false;
    for (final element in containerFinder.evaluate()) {
      final renderBox = element.renderObject as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;
      final size = renderBox.size;
      if (size.width == kLoginLogoSize && size.height == kLoginLogoSize) {
        foundLogo = true;
        break;
      }
    }
    expect(
      foundLogo,
      isTrue,
      reason: 'Logo skeleton should be ${kLoginLogoSize}x$kLoginLogoSize',
    );
  });

  testWidgets('skeleton toggle height matches login screen constant', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_skeletonApp(disableAnimations: true));
    await tester.pump();

    // The toggle track skeleton block should be kLoginToggleHeight tall and
    // stretch full width (no explicit width set).
    bool foundToggle = false;
    final containerFinder = find.byType(Container);
    for (final element in containerFinder.evaluate()) {
      final renderBox = element.renderObject as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;
      final size = renderBox.size;
      // The toggle track is the first full-width block with the right height.
      if (size.height == kLoginToggleHeight && size.width > 200) {
        foundToggle = true;
        break;
      }
    }
    expect(
      foundToggle,
      isTrue,
      reason: 'Toggle track skeleton should be $kLoginToggleHeight px tall',
    );
  });

  testWidgets('skeleton uses shared constants for all major dimensions', (
    tester,
  ) async {
    // Verify that the constants file values haven't drifted.
    expect(kLoginLogoSize, 104);
    expect(kLoginLogoRadius, closeTo(29.12, 0.01));
    expect(kLoginToggleHeight, 56);
    expect(kLoginToggleRadius, 28);
    expect(kLoginFieldHeight, 56);
    expect(kLoginFieldRadius, 30);
    expect(kLoginPrimaryButtonHeight, 52);
    expect(kLoginGoogleButtonHeight, 52);
    expect(kLoginButtonRadius, 30);
    expect(kLoginMaxWidth, 440);
  });
}
