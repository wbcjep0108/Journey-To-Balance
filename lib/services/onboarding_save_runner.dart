class OnboardingSaveRunner {
  Future<void>? _active;

  Future<void> run({
    required Iterable<String> steps,
    required Set<String> completedSteps,
    required Future<void> Function(String step) saveStep,
    required Future<void> Function(String step) markComplete,
  }) {
    final active = _active;
    if (active != null) return active;
    final operation = _run(
      steps: steps,
      completedSteps: completedSteps,
      saveStep: saveStep,
      markComplete: markComplete,
    );
    _active = operation;
    return operation;
  }

  Future<void> _run({
    required Iterable<String> steps,
    required Set<String> completedSteps,
    required Future<void> Function(String step) saveStep,
    required Future<void> Function(String step) markComplete,
  }) async {
    try {
      for (final step in steps) {
        if (completedSteps.contains(step)) continue;
        await saveStep(step);
        await markComplete(step);
      }
    } finally {
      _active = null;
    }
  }
}
