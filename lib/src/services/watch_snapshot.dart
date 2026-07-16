/// Pure model for the phone→watch state snapshot.
/// Keep this file free of Firebase and plugin imports so it stays
/// unit-testable (Firebase singletons block mocking in this repo).
class WatchSnapshot {
  final Map<String, Object> _data = {};

  Map<String, Object> get data => Map.unmodifiable(_data);

  void merge(Map<String, Object?> updates) {
    updates.forEach((key, value) {
      if (value != null) {
        _data[key] = value;
      }
    });
  }
}

String dayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// Throttles step syncs so the watch is not spammed on every step.
class StepSyncGate {
  StepSyncGate({
    this.minStepDelta = 10,
    this.minInterval = const Duration(seconds: 30),
  });

  final int minStepDelta;
  final Duration minInterval;

  int? _lastSteps;
  DateTime? _lastAt;

  bool shouldSync(int steps, DateTime now) {
    final lastSteps = _lastSteps;
    final lastAt = _lastAt;
    final due = lastSteps == null ||
        lastAt == null ||
        (steps - lastSteps).abs() >= minStepDelta ||
        now.difference(lastAt) >= minInterval;
    if (due) {
      _lastSteps = steps;
      _lastAt = now;
    }
    return due;
  }
}
