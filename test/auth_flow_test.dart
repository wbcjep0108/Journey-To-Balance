import 'dart:ui' show Tristate;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/screens/auth/login_screen.dart';
import 'package:just_budget/services/auth_service.dart';
import 'package:just_budget/services/finance_api_service.dart';
import 'package:just_budget/widgets/sensitive_action_auth.dart';

class _FakeAuthService implements AuthService {
  _FakeAuthService({this.passwordProvider = true});

  final bool passwordProvider;
  String? reauthenticatedPassword;
  bool googleReauthenticated = false;
  int googleSignInCalls = 0;

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
  Future<UserCredential> signInWithEmail(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<UserCredential?> signInWithGoogle() async {
    googleSignInCalls++;
    return null;
  }

  @override
  Future<void> signOut() async {}
}

class _FakePasswordResetApi implements PasswordResetApi {
  _FakePasswordResetApi({this.requestError, this.verifyError});

  final Object? requestError;
  final Object? verifyError;
  int requestCalls = 0;
  int verifyCalls = 0;
  int confirmCalls = 0;

  @override
  Future<void> requestPasswordReset({required String email}) async {
    requestCalls++;
    if (requestError != null) throw requestError!;
  }

  @override
  Future<String> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    verifyCalls++;
    if (verifyError != null) throw verifyError!;
    return 'reset-token';
  }

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String resetToken,
    required String newPassword,
  }) async {
    confirmCalls++;
  }
}

Widget _loginApp(
  AuthService service, {
  PasswordResetApi? passwordResetApi,
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
    home: LoginScreen(authService: service, passwordResetApi: passwordResetApi),
  );
}

Future<void> _openResetDialog(
  WidgetTester tester,
  _FakeAuthService service, {
  PasswordResetApi? passwordResetApi,
  String email = 'person@example.com',
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    _loginApp(
      service,
      textScale: textScale,
      passwordResetApi: passwordResetApi ?? _FakePasswordResetApi(),
    ),
  );
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
      final agreement = find.byType(Checkbox);
      await tester.ensureVisible(agreement);
      await tester.tap(agreement);
      await tester.pump();
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
    expect(find.byKey(const ValueKey('terms-consent-row')), findsOneWidget);
    final agreement = tester.widget<RichText>(
      find.byKey(const ValueKey('signup-legal-agreement')),
    );
    expect(
      agreement.text.toPlainText(),
      'I agree to the Terms of Service and Privacy Policy.',
    );
  });

  testWidgets('sign-up agreement blocks both actions until checked', (
    tester,
  ) async {
    final service = _FakeAuthService();
    await tester.pumpWidget(_loginApp(service));
    await tester.tap(find.byKey(const ValueKey('signup-toggle')));
    await tester.pumpAndSettle();

    final primary = find.byKey(const ValueKey('primary-auth-button'));
    await tester.ensureVisible(primary);
    await tester.tap(primary);
    await tester.pump();
    expect(
      find.text('Please agree to the Terms and Privacy Policy to continue.'),
      findsOneWidget,
    );

    final google = find.text('Continue with Google');
    await tester.ensureVisible(google);
    await tester.tap(google);
    await tester.pump();
    expect(service.googleSignInCalls, 0);

    final checkbox = find.byType(Checkbox);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    expect(
      find.text('Please agree to the Terms and Privacy Policy to continue.'),
      findsNothing,
    );
    expect((tester.widget<Checkbox>(find.byType(Checkbox)).value), isTrue);
  });

  testWidgets('login shows only the plain legal agreement line', (
    tester,
  ) async {
    await tester.pumpWidget(_loginApp(_FakeAuthService()));
    expect(find.byKey(const ValueKey('terms-consent-row')), findsNothing);
    final agreement = tester.widget<RichText>(
      find.byKey(const ValueKey('login-legal-agreement')),
    );
    expect(
      agreement.text.toPlainText(),
      'By continuing, you agree to our Terms of Service and Privacy Policy.',
    );
  });

  testWidgets('centers the complete login and signup forms vertically', (
    tester,
  ) async {
    const screenSize = Size(430, 1100);
    await tester.binding.setSurfaceSize(screenSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_loginApp(_FakeAuthService()));
    await tester.pumpAndSettle();

    Rect formRect() =>
        tester.getRect(find.byKey(const ValueKey('auth-form-container')));
    final viewportRect = tester.getRect(
      find.byKey(const ValueKey('auth-form-viewport')),
    );

    final loginRect = formRect();
    expect(
      ((loginRect.top - viewportRect.top) -
              (viewportRect.bottom - loginRect.bottom))
          .abs(),
      lessThan(8),
    );

    await tester.tap(find.byKey(const ValueKey('signup-toggle')));
    await tester.pumpAndSettle();
    final signupRect = formRect();
    expect(
      ((signupRect.top - viewportRect.top) -
              (viewportRect.bottom - signupRect.bottom))
          .abs(),
      lessThan(8),
    );
  });

  testWidgets('switching modes resets the sign-up agreement', (tester) async {
    await tester.pumpWidget(_loginApp(_FakeAuthService()));
    await tester.tap(find.byKey(const ValueKey('signup-toggle')));
    await tester.pumpAndSettle();
    final checkbox = find.byType(Checkbox);
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);

    final loginToggle = find.byKey(const ValueKey('login-toggle'));
    await tester.ensureVisible(loginToggle);
    await tester.tap(loginToggle);
    await tester.pumpAndSettle();
    final signupToggle = find.byKey(const ValueKey('signup-toggle'));
    await tester.ensureVisible(signupToggle);
    await tester.tap(signupToggle);
    await tester.pumpAndSettle();
    final resetCheckbox = find.byType(Checkbox);
    await tester.ensureVisible(resetCheckbox);
    expect(tester.widget<Checkbox>(resetCheckbox).value, isFalse);
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
    final trackRect = tester.getRect(
      find.byKey(const ValueKey('mode-toggle-track')),
    );
    final pillRect = tester.getRect(
      find.byKey(const ValueKey('selected-mode-pill')),
    );
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
    expect(trackRect.height, 56);
    expect(pillRect.height, 46);
    expect(pillRect.left - trackRect.left, 5);
    expect(pillRect.top - trackRect.top, 5);
    expect(trackRect.bottom - pillRect.bottom, 5);
    expect(pillRect.width, (trackRect.width - 10) / 2);
    expect(loginText.style?.color, Colors.white);
    expect(loginText.style?.fontWeight, FontWeight.w700);
    expect(signupText.style?.color, const Color(0xFF5B6270));
    expect(signupText.style?.fontWeight, FontWeight.w600);

    await tester.tap(find.byKey(const ValueKey('signup-toggle')));
    await tester.pumpAndSettle();
    final movedPillRect = tester.getRect(
      find.byKey(const ValueKey('selected-mode-pill')),
    );
    expect(trackRect.right - movedPillRect.right, 5);
    expect(movedPillRect.left, greaterThanOrEqualTo(trackRect.left));
    expect(movedPillRect.top, greaterThanOrEqualTo(trackRect.top));
    expect(movedPillRect.right, lessThanOrEqualTo(trackRect.right));
    expect(movedPillRect.bottom, lessThanOrEqualTo(trackRect.bottom));
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
    final trackRect = tester.getRect(
      find.byKey(const ValueKey('mode-toggle-track')),
    );
    final pillRect = tester.getRect(
      find.byKey(const ValueKey('selected-mode-pill')),
    );
    expect(trackRect.right - pillRect.right, 5);
    expect(
      find.byKey(const ValueKey('confirm-password-field')),
      findsOneWidget,
    );
  });

  group('password reset OTP flow', () {
    testWidgets('renders the email step with the prefilled email', (
      tester,
    ) async {
      await _openResetDialog(tester, _FakeAuthService());

      expect(find.text('Reset password'), findsOneWidget);
      expect(
        find.text(
          'Enter your email address and we\'ll send you a 6-digit code.',
        ),
        findsOneWidget,
      );
      final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('reset-email-field')),
      );
      expect(field.controller?.text, 'person@example.com');
      expect(find.text('Send code'), findsOneWidget);
    });

    testWidgets('invalid email blocks the request', (tester) async {
      final api = _FakePasswordResetApi();
      await _openResetDialog(
        tester,
        _FakeAuthService(),
        email: 'invalid',
        passwordResetApi: api,
      );
      await tester.tap(find.byKey(const ValueKey('reset-send-button')));
      await tester.pump();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(api.requestCalls, 0);
    });

    testWidgets('request advances to the code step and starts cooldown', (
      tester,
    ) async {
      final api = _FakePasswordResetApi();
      await _openResetDialog(tester, _FakeAuthService(), passwordResetApi: api);
      await tester.tap(find.byKey(const ValueKey('reset-send-button')));
      await tester.pumpAndSettle();

      expect(api.requestCalls, 1);
      expect(find.text('Enter the code'), findsOneWidget);
      expect(
        find.text('If an account exists for that email, a code is on its way.'),
        findsOneWidget,
      );
      var resend = tester.widget<TextButton>(
        find.byKey(const ValueKey('reset-resend-button')),
      );
      expect(resend.onPressed, isNull);
      expect(find.text('Resend code in 30s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      resend = tester.widget<TextButton>(
        find.byKey(const ValueKey('reset-resend-button')),
      );
      expect(resend.onPressed, isNotNull);
      expect(find.text('Resend code'), findsOneWidget);
    });

    testWidgets('network failure still advances with a safe error', (
      tester,
    ) async {
      final api = _FakePasswordResetApi(
        requestError: const FinanceApiException(
          code: 'unavailable',
          message: 'hidden',
        ),
      );
      await _openResetDialog(tester, _FakeAuthService(), passwordResetApi: api);
      await tester.tap(find.byKey(const ValueKey('reset-send-button')));
      await tester.pumpAndSettle();

      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.text('No internet connection.'), findsOneWidget);
    });

    testWidgets('wrong code shows the generic error', (tester) async {
      final api = _FakePasswordResetApi(
        verifyError: const FinanceApiException(
          code: 'invalid_code',
          message: 'hidden',
        ),
      );
      await _openResetDialog(tester, _FakeAuthService(), passwordResetApi: api);
      await tester.tap(find.byKey(const ValueKey('reset-send-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byKey(const ValueKey('reset-code-field')),
              matching: find.byType(TextField),
            )
            .first,
        '123456',
      );
      await tester.pump(const Duration(seconds: 1));

      expect(api.verifyCalls, 1);
      expect(find.text('Wrong or expired code'), findsOneWidget);
    });

    testWidgets('mismatched passwords are blocked and success renders', (
      tester,
    ) async {
      final api = _FakePasswordResetApi();
      await _openResetDialog(tester, _FakeAuthService(), passwordResetApi: api);
      await tester.tap(find.byKey(const ValueKey('reset-send-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byKey(const ValueKey('reset-code-field')),
              matching: find.byType(TextField),
            )
            .first,
        '123456',
      );
      await tester.pumpAndSettle();
      expect(find.text('Create a new password'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('reset-new-password-field')),
        'password-one',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reset-confirm-password-field')),
        'password-two',
      );
      await tester.tap(find.byKey(const ValueKey('reset-update-button')));
      await tester.pump();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(api.confirmCalls, 0);

      await tester.enterText(
        find.byKey(const ValueKey('reset-confirm-password-field')),
        'password-one',
      );
      await tester.tap(find.byKey(const ValueKey('reset-update-button')));
      await tester.pumpAndSettle();
      expect(api.confirmCalls, 1);
      expect(find.text('Password updated'), findsOneWidget);
      expect(
        find.text('You can now log in with your new password.'),
        findsOneWidget,
      );
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
