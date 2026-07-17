import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/domain/scoring.dart';

ScorableGoal goal({
  GoalStatus status = GoalStatus.inProgress,
  int progress = 0,
  GoalCategory category = GoalCategory.personal,
  GoalType goalType = GoalType.merit,
  double targetValue = 0,
  double currentValue = 0,
  List<ActionPlanStatus> planStatuses = const [],
}) =>
    ScorableGoal(
      status: status,
      progress: progress,
      category: category,
      goalType: goalType,
      targetValue: targetValue,
      currentValue: currentValue,
      planStatuses: planStatuses,
    );

void main() {
  group('scoreGoal', () {
    test('completed is always 100, abandoned is withdrawn', () {
      expect(scoreGoal(goal(status: GoalStatus.completed)), 100);
      expect(scoreGoal(goal(status: GoalStatus.abandoned)), isNull);
    });

    test('merit goal scores current over target, clamped', () {
      expect(scoreGoal(goal(targetValue: 100, currentValue: 40)), 40.0);
      expect(scoreGoal(goal(targetValue: 100, currentValue: 150)), 100.0);
    });

    test('merit goal with no target falls back to stored progress', () {
      expect(scoreGoal(goal(progress: 55)), 55.0);
    });

    test('milestone goal averages plan status weights', () {
      final g = goal(
        goalType: GoalType.milestone,
        planStatuses: [
          ActionPlanStatus.done,
          ActionPlanStatus.inProgress,
          ActionPlanStatus.notStarted,
        ],
      );
      expect(scoreGoal(g), 50.0);
    });

    test('milestone goal with no plans falls back to stored progress', () {
      expect(
        scoreGoal(goal(goalType: GoalType.milestone, progress: 30)),
        30.0,
      );
    });
  });

  group('scoreCategories / weightGoalScore', () {
    test('empty required category scores zero and drags the total', () {
      final categories = scoreCategories([
        goal(category: GoalCategory.personal, targetValue: 10, currentValue: 10),
        goal(
            category: GoalCategory.professional,
            targetValue: 10,
            currentValue: 5),
      ]);
      expect(categories[GoalCategory.personal], 100.0);
      expect(categories[GoalCategory.professional], 50.0);
      expect(categories[GoalCategory.contribution], 0.0);
      expect(weightGoalScore(categories), 50.0);
    });

    test('abandoned goals are excluded from the category mean', () {
      final categories = scoreCategories([
        goal(category: GoalCategory.personal, targetValue: 10, currentValue: 2),
        goal(category: GoalCategory.personal, status: GoalStatus.abandoned),
      ]);
      expect(categories[GoalCategory.personal], 20.0);
    });
  });

  group('computeStreaks', () {
    test('streak survives when today is not yet kept (grace day)', () {
      final streaks = computeStreaks(
        {'2026-07-15', '2026-07-16'},
        DateTime(2026, 7, 17),
      );
      expect(streaks.current, 2);
    });

    test('streak breaks after a fully missed day', () {
      final streaks = computeStreaks(
        {'2026-07-14', '2026-07-15'},
        DateTime(2026, 7, 17),
      );
      expect(streaks.current, 0);
      expect(streaks.longest, 2);
    });

    test('longest run is found anywhere in history', () {
      final streaks = computeStreaks(
        {'2026-07-01', '2026-07-02', '2026-07-03', '2026-07-10', '2026-07-17'},
        DateTime(2026, 7, 17),
      );
      expect(streaks.current, 1);
      expect(streaks.longest, 3);
    });
  });

  group('computeUserScore', () {
    test('overall equals goal score under current weights', () {
      final score = computeUserScore(
        UserScoreInputs(
          userId: 'u1',
          joinedAt: DateTime(2026, 6, 1),
          goals: [
            goal(
                category: GoalCategory.personal,
                targetValue: 10,
                currentValue: 10),
            goal(
                category: GoalCategory.professional,
                targetValue: 10,
                currentValue: 10),
            goal(
                category: GoalCategory.contribution,
                targetValue: 10,
                currentValue: 5),
          ],
          completionDays: ['2026-07-16', '2026-07-17'],
          checkInDays: ['2026-07-17'],
          activeCoreTaskCount: 2,
        ),
        asOf: DateTime(2026, 7, 17),
      );
      expect(score.goalScore, 83.3);
      expect(score.overallScore, 83.3);
      expect(score.currentStreak, 2);
      expect(score.coreTaskScore, greaterThan(0));
      expect(score.checkInRate, greaterThan(0));
    });

    test('window clamps to join date for expected task count', () {
      // Joined yesterday, 1 task/day, both days done → 100% completion.
      final score = computeUserScore(
        UserScoreInputs(
          userId: 'u1',
          joinedAt: DateTime(2026, 7, 16),
          goals: const [],
          completionDays: ['2026-07-16', '2026-07-17'],
          checkInDays: const [],
          activeCoreTaskCount: 1,
        ),
        asOf: DateTime(2026, 7, 17),
      );
      expect(score.taskCompletionRate, 100.0);
      expect(score.goalScore, 0.0);
      expect(score.overallScore, 0.0);
    });

    test('empty inputs produce the empty score', () {
      final score = computeUserScore(
        UserScoreInputs(
          userId: 'u1',
          joinedAt: DateTime(2026, 1, 1),
          goals: const [],
          completionDays: const [],
          checkInDays: const [],
          activeCoreTaskCount: 0,
        ),
        asOf: DateTime(2026, 7, 17),
      );
      expect(score.overallScore, 0.0);
      expect(score.currentStreak, 0);
    });
  });
}
