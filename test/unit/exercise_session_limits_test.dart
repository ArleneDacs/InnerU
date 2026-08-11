import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_session_limits.dart';

void main() {
  group('exercise session limits', () {
    test('normalizes corrupt or oversized restored goals for the picker', () {
      expect(
        normalizedExerciseSessionGoalDuration(Duration.zero),
        defaultExerciseSessionGoalDuration,
      );
      expect(
        normalizedExerciseSessionGoalDuration(const Duration(seconds: -1)),
        defaultExerciseSessionGoalDuration,
      );
      expect(
        normalizedExerciseSessionGoalDuration(const Duration(hours: 48)),
        maximumExerciseSessionGoalDuration,
      );
    });

    test('caps a forgotten session to the API-safe log duration', () {
      final elapsed = const Duration(days: 3, minutes: 4);

      expect(boundedExerciseLogDuration(elapsed), maximumExerciseLogDuration);
      expect(exerciseLogDurationWasCapped(elapsed), isTrue);
      expect(exerciseLogDurationMinutes(elapsed), 24 * 60);
    });

    test('keeps normal elapsed durations precise and validates zero', () {
      expect(
        boundedExerciseLogDuration(const Duration(seconds: 90)),
        const Duration(seconds: 90),
      );
      expect(exerciseLogDurationMinutes(const Duration(seconds: 90)), 2);
      expect(
        boundedExerciseLogDuration(Duration.zero),
        minimumExerciseLogDuration,
      );
      expect(exerciseLogDurationMinutes(Duration.zero), 1);
    });
  });
}
