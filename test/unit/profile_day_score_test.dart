import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_day_score.dart';

void main() {
  group('resolveDayScorePercent', () {
    test('returns the stored integer score as-is', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 20}),
        20,
      );
    });

    test('rounds a fractional score', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 82.6}),
        83,
      );
    });

    test('clamps a score above 100', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 140}),
        100,
      );
    });

    test('clamps a negative score to 0', () {
      expect(
        resolveDayScorePercent({'userTotalScore': -5}),
        0,
      );
    });

    test('defaults to 0 when the key is missing', () {
      expect(
        resolveDayScorePercent(<String, dynamic>{}),
        0,
      );
    });

    test('defaults to 0 when the value is not numeric', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 'not-a-number'}),
        0,
      );
    });
  });

  group('resolveDayTrackerTasks', () {
    test('uses the saved snapshot task ids when present', () {
      final tasks = resolveDayTrackerTasks({
        'call': true,
        'steps': true,
        'exercise': false,
        'meditation': true,
        'learning': true,
        'addValue': false,
        'customDailyTasks': {
          '__snapshotTaskIds': ['call', 'steps', 'meditation', 'learning'],
          'call': {'title': 'Call', 'completed': true},
          'steps': {'title': 'Steps', 'completed': true},
          'meditation': {'title': 'Meditation', 'completed': true},
          'learning': {'title': 'Learning', 'completed': true},
        },
      });

      expect(tasks.map((task) => task.title), [
        'Call',
        'Steps',
        'Meditation',
        'Learning',
      ]);
      expect(tasks.every((task) => task.completed), isTrue);
    });

    test('falls back to tracker fields when no snapshot exists', () {
      final tasks = resolveDayTrackerTasks({
        'call': true,
        'steps': true,
        'exercise': true,
        'meditation': true,
        'learning': true,
        'addValue': false,
      });

      expect(tasks.map((task) => task.title), [
        'Call',
        'Steps',
        'Exercise',
        'Meditation',
        'Learning',
        'Add Value',
      ]);
      expect(tasks.last.completed, isFalse);
    });

    test('uses live default fields when an automatic check updated them', () {
      final tasks = resolveDayTrackerTasks({
        'steps': true,
        'learning': true,
        'meditation': true,
        'customDailyTasks': {
          '__snapshotTaskIds': ['steps', 'learning', 'meditation'],
          'steps': {'title': 'Steps', 'completed': true},
          'learning': {'title': 'Learning', 'completed': true},
          'meditation': {'title': 'Meditation', 'completed': false},
        },
      });

      expect(tasks.map((task) => task.completed), [true, true, true]);
    });
  });
}
