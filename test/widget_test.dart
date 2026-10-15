import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/models/financial_entry.dart';
import 'package:just_budget/models/spend_category_option.dart';
import 'package:just_budget/screens/auth/login_screen.dart';

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
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.text('Having trouble signing in?'));
    await tester.pumpAndSettle();

    expect(find.text('Sign-in help'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Email support'), findsOneWidget);

    await tester.tap(find.text('Email support'));
    await tester.pumpAndSettle();

    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Open Gmail'), findsOneWidget);
    expect(find.text('bcueva1217@gmail.com'), findsOneWidget);
  });
}
