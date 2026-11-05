import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/widgets/bank_card_picker.dart';

void main() {
  testWidgets('shows xN badge and a minus only for queued cards', (
    tester,
  ) async {
    var added = 0;
    var removedQueued = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 110,
              child: BankCardPickerTile(
                iconAsset: 'assets/images/bank/maribank.png',
                selected: true,
                count: 2,
                canRemoveQueued: true,
                onTap: () => added++,
                onRemoveQueued: () => removedQueued++,
              ),
            ),
          ),
        ),
      ),
    );

    // Badge reflects the combined owned + queued count.
    expect(find.text('x2'), findsOneWidget);

    // Minus affordance removes only a queued card.
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.remove_rounded));
    expect(removedQueued, 1);
    expect(added, 0);
  });

  testWidgets('no minus when nothing is queued this session', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 110,
              child: BankCardPickerTile(
                iconAsset: 'assets/images/bank/maribank.png',
                selected: true,
                count: 1,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('x1'), findsOneWidget);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
  });
}
