import 'dart:ui' show Tristate;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/screens/auth/login_screen.dart';
import 'package:just_budget/services/auth_service.dart';
import 'package:just_budget/widgets/sensitive_action_auth.dart';

class _FakeAuthService implements AuthService {
  _FakeAuthService({this.passwordProvider = true, this.passwordResetError});

  final bool passwordProvider;
  final Object? passwordResetError;
  String? reauthenticatedPassword;
  bool googleReauthenticated = false;
  int passwordResetCalls = 0;

  @override
  User? get currentUser => null;
  @override
  bool get usesPasswordProvider => passwordProvider;
  @override
  bool get usesGoogleProvider => !passwordProvider;
  @override
  Future<UserCredential> createAccount(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<void> reauthenticateWithGoogle() async {
    googleReauthenticated = true;
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    reauthenticatedPassword = password;
  }

  @override
  Future<void> resendVerificationEmail() async {}
  @override
  Future<void> sendPasswordResetEmail(String email) async {
    passwordResetCalls++;
    final error = passwordResetError;
    if (error != null) throw error;
  }

  @override
  Future<UserCredential> signInWithEmail(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<User?> signInWithGoogle() async => null;
  @override
  Future<void> signOut() async {}
}

Widget _loginApp(
  AuthService service, {
  double textScale = 1,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
      ),
      child: child!,
    ),
    home: LoginScreen(authService: service),
  );
}

Future<void> _openResetDialog(
  WidgetTester tester,
  _FakeAuthService service, {
  String email = 'person@example.com',
  double textScale = 1,
}) async {
  await tester.pumpWidget(_loginApp(service, textScale: textScale));
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
  final forgotPassword = find.text('Forgot password?');
  await tester.ensureVisible(forgotPassword);
  await tester.tap(forgotPassword);
  await tester.pumpAndSettle();
}

void main() {
  group('auth validation', () {
    testWidgets('rejects invalid email and short password', (tester) async {
      await tester.pumpWidget(_loginApp(_FakeAuthService()));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'not-an-email',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'short',
      );
      final submit = find.byKey(const ValueKey('primary-auth-button'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(
        find.text('Password must be at least 8 characters.'),
        findsOneWidget,
      );
    });

    testWidgets('rejects a mismatched confirmation', (tester) async {
      await tester.pumpWidget(_loginApp(_FakeAuthService()));
      await tester.tap(find.byKey(const ValueKey('signup-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'person@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'),
        'password2',
      );
      final submit = find.byKey(const ValueKey('primary-auth-button'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();

      expect(find.text('Passwords do not match.'), findsOneWidget);
    });
  });

  test('maps auth errors without exposing raw messages', () {
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'invalid-credential')),
      'Incorrect email or password',
    );
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'wrong-password')),
      'Incorrect email or password',
    );
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'user-not-found')),
      'Incorrect email or password',
    );
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'email-already-in-use')),
      'This email is already registered. Try logging in, or use Continue with Google.',
    );
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'weak-password')),
      'Use a stronger password with at least 8 characters.',
    );
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'invalid-email')),
      'Enter a valid email address.',
    );
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'too-many-requests')),
      'Too many attempts. Please try again later.',
    );
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'network-request-failed')),
      'No internet connection.',
    );
    const raw = 'backend secret details';
    expect(friendlyAuthError(Exception(raw)), isNot(contains(raw)));
    expect(
      friendlyAuthError(FirebaseAuthException(code: 'unknown', message: raw)),
      isNot(contains(raw)),
    );
  });

  testWidgets('toggle changes login and signup fields', (tester) async {
    await tester.pumpWidget(_loginApp(_FakeAuthService()));
    expect(find.byKey(const ValueKey('confirm-password-field')), findsNothing);
    expect(find.text('Forgot password?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('signup-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('confirm-password-field')),
      findsOneWidget,
    );
    expect(find.text('Forgot password?'), findsNothing);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('toggle uses prominent selected and muted unselected styles', (
    tester,
  ) async {
    await tester.pumpWidget(_loginApp(_FakeAuthService()));
    await tester.pumpAndSettle();

    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('selected-mode-pill')),
                )
                .decoration
            as BoxDecoration;
    final loginText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('login-toggle')),
        matching: find.text('Log in'),
      ),
    );
    final signupText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('signup-toggle')),
        matching: find.text('Sign up'),
      ),
    );

    expect(decoration.color, const Color(0xFF121212));
    expect(loginText.style?.color, Colors.white);
    expect(loginText.style?.fontWeight, FontWeight.w700);
    expect(signupText.style?.color, const Color(0xFF737983));
    expect(signupText.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('toggle semantics report the selected option', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_loginApp(_FakeAuthService()));

      var loginNode = tester.getSemantics(
        find.byKey(const ValueKey('login-toggle')),
      );
      var signupNode = tester.getSemantics(
        find.byKey(const ValueKey('signup-toggle')),
      );
      expect(loginNode.label, 'Log in');
      expect(loginNode.flagsCollection.isButton, isTrue);
      expect(loginNode.flagsCollection.isSelected, Tristate.isTrue);
      expect(signupNode.label, 'Sign up');
      expect(signupNode.flagsCollection.isSelected, Tristate.isFalse);

      await tester.tap(find.byKey(const ValueKey('signup-toggle')));
      await tester.pumpAndSettle();
      loginNode = tester.getSemantics(
        find.byKey(const ValueKey('login-toggle')),
      );
      signupNode = tester.getSemantics(
        find.byKey(const ValueKey('signup-toggle')),
      );
      expect(loginNode.flagsCollection.isSelected, Tristate.isFalse);
      expect(signupNode.flagsCollection.isSelected, Tristate.isTrue);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('toggle applies final styling immediately with motion disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _loginApp(_FakeAuthService(), disableAnimations: true),
    );
    await tester.tap(find.byKey(const ValueKey('signup-toggle')));
    await tester.pump();

    final signupText = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('signup-toggle')),
        matching: find.text('Sign up'),
      ),
    );
    expect(signupText.style?.color, Colors.white);
    expect(signupText.style?.fontWeight, FontWeight.w700);
    expect(
      find.byKey(const ValueKey('confirm-password-field')),
      findsOneWidget,
    );
  });

  group('reset password dialog', () {
    testWidgets('shows the styled form with the prefilled email', (
      tester,
    ) async {
      await _openResetDialog(tester, _FakeAuthService());

      expect(find.byIcon(Icons.lock_reset_outlined), findsOneWidget);
      expect(find.text('Reset password'), findsOneWidget);
      expect(
        find.text(
          'Enter your email and we\'ll send you a link to reset your password.',
        ),
        findsOneWidget,
      );
      final emailField = tester.widget<TextFormField>(
        find.byKey(const ValueKey('reset-email-field')),
      );
      expect(emailField.controller?.text, 'person@example.com');
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Send reset link'), findsOneWidget);
    });

    testWidgets('invalid email stays inline and does not call the service', (
      tester,
    ) async {
      final service = _FakeAuthService();
      await _openResetDialog(tester, service, email: 'invalid');
      final send = find.byKey(const ValueKey('reset-send-button'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(service.passwordResetCalls, 0);
    });

    testWidgets('valid email shows the neutral success view', (tester) async {
      final service = _FakeAuthService();
      await _openResetDialog(tester, service);
      final send = find.byKey(const ValueKey('reset-send-button'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(service.passwordResetCalls, 1);
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(
        find.text(
          'If an account exists for that email, a reset link is on its way.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('user-not-found shows the same neutral success view', (
      tester,
    ) async {
      final service = _FakeAuthService(
        passwordResetError: FirebaseAuthException(code: 'user-not-found'),
      );
      await _openResetDialog(tester, service);
      final send = find.byKey(const ValueKey('reset-send-button'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'If an account exists for that email, a reset link is on its way.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('user'), findsNothing);
    });

    testWidgets('rate-limit failure stays inline', (tester) async {
      final service = _FakeAuthService(
        passwordResetError: FirebaseAuthException(code: 'too-many-requests'),
      );
      await _openResetDialog(tester, service);
      final send = find.byKey(const ValueKey('reset-send-button'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(
        find.text('Too many attempts. Please try again later.'),
        findsOneWidget,
      );
    });

    testWidgets('network failure stays inline', (tester) async {
      final service = _FakeAuthService(
        passwordResetError: FirebaseAuthException(
          code: 'network-request-failed',
        ),
      );
      await _openResetDialog(tester, service);
      final send = find.byKey(const ValueKey('reset-send-button'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(find.text('No internet connection.'), findsOneWidget);
    });

    testWidgets('resend is disabled during cooldown and then re-enabled', (
      tester,
    ) async {
      await _openResetDialog(tester, _FakeAuthService());
      final send = find.byKey(const ValueKey('reset-send-button'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();

      var resend = tester.widget<TextButton>(
        find.byKey(const ValueKey('reset-resend-button')),
      );
      expect(resend.onPressed, isNull);
      expect(find.text('Resend in 30s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      resend = tester.widget<TextButton>(
        find.byKey(const ValueKey('reset-resend-button')),
      );
      expect(resend.onPressed, isNotNull);
      expect(find.text('Resend link'), findsOneWidget);
    });

    testWidgets('Done closes the success view', (tester) async {
      await _openResetDialog(tester, _FakeAuthService());
      final send = find.byKey(const ValueKey('reset-send-button'));
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('reset-done-button')));
      await tester.pumpAndSettle();

      expect(find.text('Check your inbox'), findsNothing);
    });

    testWidgets('does not overflow at 360px and 1.3x text scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);

      await _openResetDialog(tester, _FakeAuthService(), textScale: 1.3);
      await tester.showKeyboard(
        find.byKey(const ValueKey('reset-email-field')),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('does not overflow at 360px and 1.3x text scale', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_loginApp(_FakeAuthService(), textScale: 1.3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('signup-toggle')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reauthenticates password accounts with entered password', (
    tester,
  ) async {
    final service = _FakeAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFirebaseReauthentication(
              context: context,
              authService: service,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reauth-password-field')),
      'correct password',
    );
    await tester.tap(find.byKey(const ValueKey('reauth-confirm-button')));
    await tester.pumpAndSettle();
    expect(service.reauthenticatedPassword, 'correct password');
  });

  testWidgets('reauthenticates Google accounts with Google', (tester) async {
    final service = _FakeAuthService(passwordProvider: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFirebaseReauthentication(
              context: context,
              authService: service,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reauth-confirm-button')));
    await tester.pumpAndSettle();
    expect(service.googleReauthenticated, isTrue);
  });
}
