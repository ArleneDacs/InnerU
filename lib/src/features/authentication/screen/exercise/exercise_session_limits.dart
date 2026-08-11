/// Client-side limits that match the exercise log API contract.
///
/// A workout goal must fit the picker (0-23:59:59), while a recorded elapsed
/// duration can be exactly 24 hours. Keeping these two limits separate lets a
/// recovered, forgotten session remain recoverable without ever sending an
/// invalid duration to the API.
const Duration defaultExerciseSessionGoalDuration = Duration(minutes: 5);
const Duration maximumExerciseSessionGoalDuration = Duration(
  hours: 23,
  minutes: 59,
  seconds: 59,
);
const Duration maximumExerciseLogDuration = Duration(hours: 24);
const Duration minimumExerciseLogDuration = Duration(seconds: 1);

/// Makes persisted goal data safe for the available duration-picker values.
/// Missing, zero, negative, and corrupt values get the normal five-minute
/// default; oversized legacy values are capped to the picker maximum.
Duration normalizedExerciseSessionGoalDuration(Duration rawDuration) {
  if (rawDuration <= Duration.zero) {
    return defaultExerciseSessionGoalDuration;
  }
  if (rawDuration > maximumExerciseSessionGoalDuration) {
    return maximumExerciseSessionGoalDuration;
  }
  return rawDuration;
}

/// Bounds elapsed wall-clock time before it is sent to the exercise API.
/// A session left open for days can therefore still be stopped and saved as a
/// valid 24-hour maximum instead of becoming permanently unsaveable.
Duration boundedExerciseLogDuration(Duration elapsed) {
  if (elapsed <= Duration.zero) {
    return minimumExerciseLogDuration;
  }
  if (elapsed > maximumExerciseLogDuration) {
    return maximumExerciseLogDuration;
  }
  return elapsed;
}

bool exerciseLogDurationWasCapped(Duration elapsed) =>
    elapsed > maximumExerciseLogDuration;

/// Uses the same nearest-minute representation as the server after first
/// enforcing the valid seconds range.
int exerciseLogDurationMinutes(Duration elapsed) {
  return (boundedExerciseLogDuration(elapsed).inSeconds / 60)
      .round()
      .clamp(
        1,
        maximumExerciseLogDuration.inMinutes,
      )
      .toInt();
}
