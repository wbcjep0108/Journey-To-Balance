import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/widgets/sign_out_confirmation_dialog.dart';

Future<void> _openDialog(
  WidgetTester tester,
  ValueChanged<bool?> onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                onResult(
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => const SignOutConfirmationDialog(),
                  ),
                );
              },
              child: const Text('Sign Out'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Sign Out'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Cancel dismisses the sign-out confirmation with false', (
    tester,
  ) async {
    bool? result;
    await _openDialog(tester, (value) => result = value);

    expect(find.text('Are you sure you want to sign out?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sign-out-cancel')));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('Sign out?'), findsNothing);
  });

  testWidgets('Confirm dismisses the sign-out confirmation with true', (
    tester,
  ) async {
    bool? result;
    await _openDialog(tester, (value) => result = value);

    await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('Sign out?'), findsNothing);
  });
}
