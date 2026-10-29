import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/providers/app_lock_provider.dart';
import 'package:just_budget/screens/account/security_settings_page.dart';
import 'package:just_budget/services/auth_service.dart';
import 'package:just_budget/services/finance_api_service.dart';
import 'package:provider/provider.dart';

class _MockUser implements User {
  _MockUser({required this.email, required this.uid});

  @override
  final String email;

  @override
  final String uid;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockAuthService implements AuthService {
  _MockAuthService({
    required this.mockUser,
    this.isPassword = true,
    this.reauthError,
  });

  final User mockUser;
  final bool isPassword;
  final Object? reauthError;

  int reauthPasswordCalls = 0;
  int reauthGoogleCalls = 0;
  int signOutCalls = 0;
  String? lastPassword;

  @override
  User? get currentUser => mockUser;

  @override
  bool get usesPasswordProvider => isPassword;

  @override
  bool get usesGoogleProvider => !isPassword;

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    reauthPasswordCalls++;
    lastPassword = password;
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> reauthenticateWithGoogle() async {
    reauthGoogleCalls++;
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockFinanceApiService implements FinanceApiService {
  _MockFinanceApiService({this.deleteError});

  final Object? deleteError;
  int deleteCalls = 0;
  String? lastConfirmedEmail;

  @override
  Future<void> deleteAccount({required String confirmationEmail}) async {
    deleteCalls++;
    lastConfirmedEmail = confirmationEmail;
    if (deleteError != null) throw deleteError!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp({
  required AuthService authService,
  required FinanceApiService financeApiService,
}) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
      ],
      child: SecuritySettingsPage(
        authService: authService,
        financeApiService: financeApiService,
      ),
    ),
  );
}

void main() {
  testWidgets('delete account button is disabled until email matches', (
    tester,
  ) async {
    final user = _MockUser(email: 'user@example.com', uid: 'uid123');
    final auth = _MockAuthService(mockUser: user, isPassword: true);
    final finance = _MockFinanceApiService();

    await tester.pumpWidget(
      _buildTestApp(authService: auth, financeApiService: finance),
    );
    await tester.pumpAndSettle();

    // Scroll to and tap "Delete Account" tile
    await tester.scrollUntilVisible(
      find.text('Delete Account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();

    // Confirm button is disabled initially
    final confirmBtn = find.byKey(
      const ValueKey('delete-account-confirm-button'),
    );
    expect(confirmBtn, findsOneWidget);
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);

    // Enter wrong email
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-email-field')),
      'wrong@example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-password-field')),
      'password123',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);

    // Enter matching email
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-email-field')),
      'user@example.com',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);
  });

  testWidgets(
    'delete account executes reauthentication and deleteAccount on valid input',
    (tester) async {
      final user = _MockUser(email: 'user@example.com', uid: 'uid123');
      final auth = _MockAuthService(mockUser: user, isPassword: true);
      final finance = _MockFinanceApiService();

      await tester.pumpWidget(
        _buildTestApp(authService: auth, financeApiService: finance),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Delete Account'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('delete-account-email-field')),
        '  User@Example.Com  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-password-field')),
        'Secret123',
      );
      await tester.pumpAndSettle();

      final confirmBtn = find.byKey(
        const ValueKey('delete-account-confirm-button'),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(auth.reauthPasswordCalls, 1);
      expect(auth.lastPassword, 'Secret123');
      expect(finance.deleteCalls, 1);
      expect(finance.lastConfirmedEmail, 'User@Example.Com');
    },
  );

  testWidgets(
    'displays error when reauthentication fails and does not delete',
    (tester) async {
      final user = _MockUser(email: 'user@example.com', uid: 'uid123');
      final auth = _MockAuthService(
        mockUser: user,
        isPassword: true,
        reauthError: FirebaseAuthException(code: 'wrong-password'),
      );
      final finance = _MockFinanceApiService();

      await tester.pumpWidget(
        _buildTestApp(authService: auth, financeApiService: finance),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Delete Account'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Delete Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('delete-account-email-field')),
        'user@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-password-field')),
        'wrongPass',
      );
      await tester.pumpAndSettle();

      final confirmBtn = find.byKey(
        const ValueKey('delete-account-confirm-button'),
      );
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(auth.reauthPasswordCalls, 1);
      expect(finance.deleteCalls, 0); // Not called!
      expect(find.text('Incorrect email or password'), findsOneWidget);
    },
  );

  testWidgets('google user flow omits password field and calls reauthGoogle', (
    tester,
  ) async {
    final user = _MockUser(email: 'googleuser@example.com', uid: 'gid456');
    final auth = _MockAuthService(mockUser: user, isPassword: false);
    final finance = _MockFinanceApiService();

    await tester.pumpWidget(
      _buildTestApp(authService: auth, financeApiService: finance),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Delete Account'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Delete Account'));
    await tester.pumpAndSettle();

    // Password field should not be present
    expect(
      find.byKey(const ValueKey('delete-account-password-field')),
      findsNothing,
    );

    // Enter email
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-email-field')),
      'googleuser@example.com',
    );
    await tester.pumpAndSettle();

    final confirmBtn = find.byKey(
      const ValueKey('delete-account-confirm-button'),
    );
    expect(find.text('Verify with Google & Delete'), findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(auth.reauthGoogleCalls, 1);
    expect(finance.deleteCalls, 1);
    expect(finance.lastConfirmedEmail, 'googleuser@example.com');
  });
}
