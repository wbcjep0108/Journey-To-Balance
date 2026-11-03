import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/widgets/skeleton.dart';

Widget _app({required bool loading, bool disableAnimations = false}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: child!,
    ),
    home: Scaffold(
      body: SkeletonSwitcher(
        loading: loading,
        skeleton: const SkeletonShimmer(
          child: SkeletonBlock(
            key: ValueKey('test-skeleton-block'),
            width: 120,
            height: 20,
          ),
        ),
        child: const Text('Loaded content'),
      ),
    ),
  );
}

void main() {
  testWidgets('delays skeleton and keeps it visible for at least 400ms', (
    tester,
  ) async {
    var loading = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return _app(loading: loading);
        },
      ),
    );

    await tester.pump(const Duration(milliseconds: 149));
    expect(find.byKey(const ValueKey('test-skeleton-block')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('test-skeleton-block')), findsOneWidget);

    setHostState(() => loading = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 399));
    expect(find.text('Loaded content'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('Loaded content'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 181));
    expect(find.byKey(const ValueKey('test-skeleton-block')), findsNothing);
  });

  testWidgets('a load shorter than 150ms never shows a skeleton', (
    tester,
  ) async {
    var loading = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return _app(loading: loading);
        },
      ),
    );

    await tester.pump(const Duration(milliseconds: 100));
    setHostState(() => loading = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('test-skeleton-block')), findsNothing);
    expect(find.text('Loaded content'), findsOneWidget);
  });

  testWidgets('reduced motion uses a static block and swaps instantly', (
    tester,
  ) async {
    var loading = true;
    late StateSetter setHostState;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setHostState = setState;
          return _app(loading: loading, disableAnimations: true);
        },
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    final container = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const ValueKey('test-skeleton-block')),
        matching: find.byType(Container),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0xFFF1F2F4));
    expect(decoration.gradient, isNull);
    expect(tester.hasRunningAnimations, isFalse);

    setHostState(() => loading = false);
    await tester.pump();
    expect(find.byKey(const ValueKey('test-skeleton-block')), findsNothing);
    expect(find.text('Loaded content'), findsOneWidget);
  });
}
