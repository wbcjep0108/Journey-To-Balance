import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_budget/services/onboarding_save_runner.dart';

void main() {
  const steps = ['currency', 'budget', 'wallet', 'balance', 'completion'];

  for (final failedStep in steps) {
    test(
      'retry after $failedStep failure does not repeat completed steps',
      () async {
        final runner = OnboardingSaveRunner();
        final completed = <String>{};
        final calls = <String>[];
        var shouldFail = true;

        Future<void> run() => runner.run(
          steps: steps,
          completedSteps: completed,
          saveStep: (step) async {
            calls.add(step);
            if (step == failedStep && shouldFail) {
              shouldFail = false;
              throw StateError('failed');
            }
          },
          markComplete: (step) async => completed.add(step),
        );

        await expectLater(run(), throwsStateError);
        final completedBeforeFailure = Set<String>.from(completed);
        await run();

        for (final step in completedBeforeFailure) {
          expect(calls.where((call) => call == step).length, 1);
        }
        expect(completed, containsAll(steps));
      },
    );
  }

  test('concurrent finish attempts run one set of saves', () async {
    final runner = OnboardingSaveRunner();
    final completed = <String>{};
    final blocker = Completer<void>();
    var calls = 0;

    Future<void> run() => runner.run(
      steps: const ['budget'],
      completedSteps: completed,
      saveStep: (_) async {
        calls++;
        await blocker.future;
      },
      markComplete: (step) async => completed.add(step),
    );

    final first = run();
    final second = run();
    expect(identical(first, second), isTrue);
    blocker.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
  });
}
