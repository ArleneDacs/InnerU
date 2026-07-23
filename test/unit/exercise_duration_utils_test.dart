import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/exercise/exercise_duration_utils.dart';

void main() {
  group('Exercise duration helpers', () {
    test('converts picker selections into an exact duration', () {
      const selection = ExerciseDurationSelection(
        hours: 1,
        minutes: 2,
        seconds: 3,
      );

      final duration = exerciseDurationFromSelection(selection);

      expect(duration.inSeconds, 3723);
      expect(formatExerciseDuration(duration), '1h 02m 03s');
    });

    test('breaks duration back into picker values', () {
      final selection = exerciseDurationSelectionFromDuration(
        const Duration(hours: 2, minutes: 5, seconds: 9),
      );

      expect(selection.hours, 2);
      expect(selection.minutes, 5);
      expect(selection.seconds, 9);
    });

    test('formats sub-hour durations with seconds intact', () {
      expect(formatExerciseDuration(const Duration(seconds: 59)), '0m 59s');
      expect(formatExerciseDuration(const Duration(minutes: 10)), '10m 00s');
    });
  });
}
