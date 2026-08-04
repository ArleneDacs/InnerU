import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';

void main() {
  group('ActivityStreakService.activeCurrentStreak', () {
    test('keeps the streak when the activity was completed today', () {
      final now = DateTime(2026, 8, 4, 21, 0);
      final streak = ActivityStreakService.activeCurrentStreak(
        lastDate: '2026-08-04',
        currentStreak: 12,
        now: now,
      );
      expect(streak, 12);
    });

    test('keeps the streak when the activity was completed yesterday', () {
      final now = DateTime(2026, 8, 4, 6, 0);
      final streak = ActivityStreakService.activeCurrentStreak(
        lastDate: '2026-08-03',
        currentStreak: 12,
        now: now,
      );
      expect(streak, 12);
    });

    test('resets to 0 once a full day is missed', () {
      final now = DateTime(2026, 8, 4);
      final streak = ActivityStreakService.activeCurrentStreak(
        lastDate: '2026-08-02',
        currentStreak: 12,
        now: now,
      );
      expect(streak, 0);
    });

    test('returns 0 when there is no last-completed date yet', () {
      final streak = ActivityStreakService.activeCurrentStreak(
        lastDate: null,
        currentStreak: 5,
        now: DateTime(2026, 8, 4),
      );
      expect(streak, 0);
    });

    test('treats an empty string last date the same as no date', () {
      final streak = ActivityStreakService.activeCurrentStreak(
        lastDate: '',
        currentStreak: 5,
        now: DateTime(2026, 8, 4),
      );
      expect(streak, 0);
    });
  });

  group('ActivityStreakService.readInt', () {
    test('passes through an int unchanged', () {
      expect(ActivityStreakService.readInt(7), 7);
    });

    test('rounds/truncates a num', () {
      expect(ActivityStreakService.readInt(7.9), 7);
    });

    test('parses a numeric string', () {
      expect(ActivityStreakService.readInt('9'), 9);
    });

    test('defaults to 0 for null or unparsable values', () {
      expect(ActivityStreakService.readInt(null), 0);
      expect(ActivityStreakService.readInt('not-a-number'), 0);
    });
  });

  group('ActivityStreakService.readRewards', () {
    test('returns a string-keyed copy of a reward map', () {
      final rewards = ActivityStreakService.readRewards({
        'first_breath': '2026-08-01',
        'steady_flame': '2026-08-05',
      });
      expect(rewards, {
        'first_breath': '2026-08-01',
        'steady_flame': '2026-08-05',
      });
    });

    test('returns an empty map for non-map input', () {
      expect(ActivityStreakService.readRewards(null), <String, dynamic>{});
      expect(ActivityStreakService.readRewards('nope'), <String, dynamic>{});
    });
  });

  group('ActivityStreakService milestones', () {
    test('every activity type has 6 milestones at 3/7/14/30/60/100 days', () {
      for (final type in ActivityStreakType.values) {
        final milestones = ActivityStreakService.milestonesFor(type);
        expect(milestones.map((m) => m.days).toList(), [3, 7, 14, 30, 60, 100]);
      }
    });

    test('milestone ids are unique within an activity type', () {
      for (final type in ActivityStreakType.values) {
        final ids = ActivityStreakService.milestonesFor(type).map((m) => m.id);
        expect(ids.toSet().length, ids.length);
      }
    });
  });

  group('ActivityStreakService field name helpers', () {
    test('produce the camelCase keys the backend payload actually uses', () {
      expect(
        ActivityStreakService.currentFieldFor(ActivityStreakType.exercise),
        'exerciseStreakCurrent',
      );
      expect(
        ActivityStreakService.longestFieldFor(ActivityStreakType.steps),
        'stepsStreakLongest',
      );
      expect(
        ActivityStreakService.lastDateFieldFor(ActivityStreakType.fasting),
        'fastingStreakLastDate',
      );
      expect(
        ActivityStreakService.rewardsFieldFor(ActivityStreakType.meditation),
        'meditationStreakRewards',
      );
    });
  });
}
