import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/daily_score_service.dart';

void main() {
  group('DailyScoreService', () {
    test('scores daily tracker as a 0-100 completion percentage', () {
      final tracker = <String, dynamic>{
        'meditation': true,
        'steps': true,
        'exercise': false,
        'call': false,
      };

      final summary = DailyScoreService.summarizeTracker(
        tracker,
        dailyTrackerIds: const ['meditation', 'steps', 'exercise', 'call'],
      );

      expect(summary.dailyTrackerScore, 50);
      expect(summary.todoListIncludedInTotal, isFalse);
      expect(summary.totalPoints, 50);
    });

    test('averages the daily score with todo list contribution when included',
        () {
      final tracker = <String, dynamic>{
        'meditation': true,
        'steps': true,
        'exercise': true,
        'call': false,
        'todoListScore': 80,
        'todoListScoreDailyContribution': 80,
        'todoListIncludedInTotal': true,
      };

      final summary = DailyScoreService.summarizeTracker(
        tracker,
        dailyTrackerIds: const ['meditation', 'steps', 'exercise', 'call'],
      );

      expect(summary.dailyTrackerScore, 75);
      expect(summary.todoListScore, 80);
      expect(summary.todoListScoreContribution, 80);
      expect(summary.todoListIncludedInTotal, isTrue);
      expect(summary.totalPoints, 77.5);
    });

    test('returns 100 when every daily task is done', () {
      final tracker = <String, dynamic>{
        'meditation': true,
        'steps': true,
        'exercise': true,
        'call': true,
      };

      final summary = DailyScoreService.summarizeTracker(
        tracker,
        dailyTrackerIds: const ['meditation', 'steps', 'exercise', 'call'],
      );

      expect(summary.dailyTrackerScore, 100);
      expect(summary.totalPoints, 100);
    });

    test('resolveDisplayTotalPoints prefers the shared 0-100 formula', () {
      final score = DailyScoreService.resolveDisplayTotalPoints({
        'dailyTrackerScore': 60,
        'todoListScore': 80,
        'todoListScoreDailyContribution': 80,
        'todoListIncludedInTotal': true,
      });

      expect(score, 70);
    });
  });
}
