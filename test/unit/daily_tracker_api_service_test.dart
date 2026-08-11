import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/daily_tracker_api_service.dart';

void main() {
  group('DailyTrackerApiService.completedActivityFields', () {
    test('includes only the activity that was completed', () {
      expect(
        DailyTrackerApiService.completedActivityFields(meditation: true),
        {'meditation': true},
      );
      expect(
        DailyTrackerApiService.completedActivityFields(learning: true),
        {'learning': true},
      );
      expect(
        DailyTrackerApiService.completedActivityFields(addValue: true),
        {'addValue': true},
      );
      expect(
        DailyTrackerApiService.completedActivityFields(steps: true),
        {'steps': true},
      );
    });

    test('omits false activities instead of sending destructive false flags',
        () {
      expect(DailyTrackerApiService.completedActivityFields(), isEmpty);
      expect(
        DailyTrackerApiService.completedActivityFields(
          meditation: true,
          steps: false,
          learning: false,
          addValue: false,
        ),
        {'meditation': true},
      );
    });
  });

  group('DailyTrackerApiService.newStepGoalRewardsFromResponse', () {
    test('reads only newly unlocked server-authoritative Step medals', () {
      final rewards = DailyTrackerApiService.newStepGoalRewardsFromResponse({
        'stepGoalAchievement': {
          'currentStreak': 3,
          'newRewards': [
            {
              'id': 'first_stride',
              'title': 'First Stride',
              'tier': 'Bronze',
              'days': 3,
              'description': 'Reached your step goal for 3 days in a row.',
              'unlockedAt': '2026-08-03',
            },
          ],
        },
      });

      expect(rewards, hasLength(1));
      expect(rewards.single.id, 'first_stride');
      expect(rewards.single.title, 'First Stride');
      expect(rewards.single.days, 3);
      expect(rewards.single.unlockedAt, '2026-08-03');
    });

    test('ignores missing or malformed achievement payloads', () {
      expect(
        DailyTrackerApiService.newStepGoalRewardsFromResponse(const {}),
        isEmpty,
      );
      expect(
        DailyTrackerApiService.newStepGoalRewardsFromResponse({
          'stepGoalAchievement': {
            'newRewards': [
              {'id': '', 'title': 'Missing id'},
              {'id': 'missing-title', 'title': ''},
              'not-a-map',
            ],
          },
        }),
        isEmpty,
      );
    });
  });
}
