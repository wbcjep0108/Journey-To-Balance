import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/services/auth_service.dart';
import 'package:just_budget/services/logout_transition_controller.dart';
import 'package:just_budget/widgets/logout_skeleton.dart';

Widget _transitionApp(
  LogoutTransitionController controller, {
  bool disableAnimations = false,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: disableAnimations,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.active) {
          if (controller.showLogin) {
            return const Scaffold(
              key: ValueKey('ready-login-screen'),
              body: SizedBox.expand(),
            );
          }
          return Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: controller.begin,
                child: const Text('Confirm logout'),
              ),
            ),
          );
        }
        return LogoutTransitionView(
          showLogin: controller.showLogin,
          loginScreen: const Scaffold(
            key: ValueKey('ready-login-screen'),
            body: SizedBox.expand(),
          ),
          onFinished: controller.finish,
        );
      },
    ),
  );
}

void _markReady(LogoutTransitionController controller) {
  controller
    ..markLogoutComplete()
    ..markSignedOut()
    ..markLoginReady();
}

void main() {
  testWidgets('skeleton appears immediately and stays for at least 500ms', (
    tester,
  ) async {
    final controller = LogoutTransitionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_transitionApp(controller));

    await tester.tap(find.text('Confirm logout'));
    await tester.pump();
    expect(find.byKey(const ValueKey('logout-skeleton')), findsOneWidget);

    _markReady(controller);
    await tester.pump(const Duration(milliseconds: 499));
    expect(find.byKey(const ValueKey('ready-login-screen')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('ready-login-screen')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 201));
    await tester.pump();
    expect(find.byKey(const ValueKey('logout-skeleton')), findsNothing);
  });

  testWidgets('waits for logout, auth state, and login readiness', (
    tester,
  ) async {
    final controller = LogoutTransitionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_transitionApp(controller));
    controller.begin();
    await tester.pump(const Duration(milliseconds: 500));

    controller.markLogoutComplete();
    controller.markSignedOut();
    await tester.pump();
    expect(find.byKey(const ValueKey('ready-login-screen')), findsNothing);

    controller.markLoginReady();
    await tester.pump();
    expect(find.byKey(const ValueKey('ready-login-screen')), findsOneWidget);
    controller.abort();
    await tester.pump();
  });

  testWidgets('hard cap reveals login after three seconds', (tester) async {
    final controller = LogoutTransitionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_transitionApp(controller));
    controller.begin();
    await tester.pump();

    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('ready-login-screen')), findsOneWidget);
    controller.abort();
    await tester.pump();
  });

  testWidgets('reduced motion uses static placeholders and instant swap', (
    tester,
  ) async {
    final controller = LogoutTransitionController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _transitionApp(controller, disableAnimations: true),
    );
    controller.begin();
    await tester.pump();
    expect(find.byKey(const ValueKey('logout-skeleton')), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);

    _markReady(controller);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byKey(const ValueKey('ready-login-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('logout-skeleton')), findsNothing);
  });

  testWidgets('skeleton does not overflow at 360px and 1.3x text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    final controller = LogoutTransitionController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_transitionApp(controller, textScale: 1.3));
    controller.begin();
    await tester.pump();
    expect(find.byKey(const ValueKey('logout-skeleton')), findsOneWidget);
    expect(tester.takeException(), isNull);
    controller.abort();
    await tester.pump();
  });

  test('Google cleanup timeout still signs out of Firebase', () async {
    final googleCleanup = Completer<void>();
    var firebaseSignOutCalls = 0;

    await signOutWithGoogleCleanup(
      usesGoogleProvider: true,
      googleSignOut: () => googleCleanup.future,
      firebaseSignOut: () async {
        firebaseSignOutCalls++;
      },
      googleTimeout: const Duration(milliseconds: 10),
    );

    expect(firebaseSignOutCalls, 1);
  });
}
