import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/models/spend_category_option.dart';
import 'package:just_budget/screens/auth/login_screen.dart';
import 'package:just_budget/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _WidgetTestAuthService implements AuthService {
  int googleSignInCalls = 0;

  @override
  User? get currentUser => null;
  @override
  bool get usesGoogleProvider => false;
  @override
  bool get usesPasswordProvider => true;
  @override
  Future<UserCredential> createAccount(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<void> reauthenticateWithGoogle() async {}
  @override
  Future<void> reauthenticateWithPassword(String password) async {}
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

Future<void> _openSignInHelp(
  WidgetTester tester,
  _WidgetTestAuthService service, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: LoginScreen(authService: service),
    ),
  );
  final helpLink = find.text('Having trouble signing in?');
  await tester.ensureVisible(helpLink);
  await tester.tap(helpLink);
  await tester.pumpAndSettle();
}

void main() {
  test('financial entry copy preserves identity and creation time', () {
    final createdAt = DateTime(2026, 7, 28);
    final entry = FinancialEntry(
      id: 'entry-id',
      title: 'Electricity',
      amount: 500,
      createdAt: createdAt,
    );

    final updated = entry.copyWith(
      title: 'Water',
      amount: 250,
      iconAsset: 'assets/images/icons_bills/water.png',
    );

    expect(updated.id, entry.id);
    expect(updated.createdAt, createdAt);
    expect(updated.title, 'Water');
    expect(updated.amount, 250);
    expect(updated.iconAsset, 'assets/images/icons_bills/water.png');
  });

  test('transaction icons have category fallbacks and breakdown labels', () {
    expect(
      SpendCategoryPresets.defaultIconAsset(FinancialCategory.bills),
      'material:receipt_long',
    );
    expect(
      SpendCategoryPresets.defaultIconAsset(FinancialCategory.savings),
      'material:savings',
    );
    expect(
      SpendCategoryPresets.labelForAsset(
        FinancialCategory.personal,
        'material:shopping_bag',
      ),
      'Shopping',
    );
    expect(
      SpendCategoryPresets.labelForAsset(
        FinancialCategory.bills,
        'assets/images/icons_bills/water.png',
      ),
      'Water',
    );
  });

  testWidgets('sign-in help button opens troubleshooting dialog', (
    tester,
  ) async {
    await _openSignInHelp(tester, _WidgetTestAuthService());

    expect(find.text('Sign-in help'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Email support'), findsOneWidget);

    final emailCenter = tester.getCenter(
      find.byKey(const ValueKey('sign-in-help-email-support')),
    );
    final closeCenter = tester.getCenter(
      find.byKey(const ValueKey('sign-in-help-close')),
    );
    final retryCenter = tester.getCenter(
      find.byKey(const ValueKey('sign-in-help-try-again')),
    );
    expect(emailCenter.dy, lessThan(closeCenter.dy));
    expect(closeCenter.dy, retryCenter.dy);

    await tester.tap(find.text('Email support'));
    await tester.pumpAndSettle();

    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Open Gmail'), findsOneWidget);
    expect(find.text('bcueva1217@gmail.com'), findsOneWidget);
  });

  testWidgets('sign-in help Close dismisses the dialog', (tester) async {
    await _openSignInHelp(tester, _WidgetTestAuthService());
    await tester.tap(find.byKey(const ValueKey('sign-in-help-close')));
    await tester.pumpAndSettle();

    expect(find.text('Sign-in help'), findsNothing);
  });

  testWidgets('sign-in help Try again retries Google sign-in', (tester) async {
    final service = _WidgetTestAuthService();
    await _openSignInHelp(tester, service);
    await tester.tap(find.byKey(const ValueKey('sign-in-help-try-again')));
    await tester.pumpAndSettle();

    expect(find.text('Sign-in help'), findsNothing);
    expect(service.googleSignInCalls, 1);
  });

  testWidgets('sign-in help fits at 1.3x on a 360 wide screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);

    await _openSignInHelp(tester, _WidgetTestAuthService(), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
