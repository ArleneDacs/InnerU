/// The scoring engine — a pure-Dart port of A12-Tracker's
/// `src/lib/scoring.ts` compute half. Everything here derives scores from
/// rows the caller has already fetched; nothing touches Firestore. The
/// persist half (snapshots) arrives in Phase 3.
///
/// Every score is on 0–100 so users, groups, and coaches are comparable on
/// one axis without rescaling.
library;

import 'dart:math' as math;

import 'day_keys.dart';
import 'domain.dart';

double _round1(double n) => (n * 10).round() / 10;
double _clamp(double n, [double lo = 0, double hi = 100]) =>
    math.min(hi, math.max(lo, n));

// ---------------------------------------------------------------------------
// Goal scoring
// ---------------------------------------------------------------------------

class ScorableGoal {
  const ScorableGoal({
    required this.status,
    required this.progress,
    required this.category,
    required this.goalType,
    required this.targetValue,
    required this.currentValue,
    this.planStatuses = const [],
  });

  final GoalStatus status;

  /// The cached 0–100 mirror stored on the goal row.
  final int progress;
  final GoalCategory category;
  final GoalType goalType;
  final double targetValue;
  final double currentValue;
  final List<ActionPlanStatus> planStatuses;
}

/// A goal's score on 0–100, or null when ABANDONED — withdrawn from every
/// average rather than scored zero. If dropping an outgrown goal permanently
/// damaged your score, nobody would ever drop one honestly.
double? scoreGoal(ScorableGoal goal) {
  if (goal.status == GoalStatus.abandoned) return null;
  if (goal.status == GoalStatus.completed) return 100;

  // A MILESTONE goal is exactly as done as its action plans: the average of
  // their status weights. With no plans yet it falls back to stored progress.
  if (goal.goalType == GoalType.milestone) {
    if (goal.planStatuses.isEmpty) return _clamp(goal.progress.toDouble());
    final sum = goal.planStatuses.fold<int>(0, (acc, s) => acc + s.weight);
    return _round1(sum / goal.planStatuses.length);
  }

  // A MERIT goal is its numeric measure: how far current has come toward
  // target. With no target set, the stored progress stands in.
  if (goal.targetValue > 0) {
    return _round1(_clamp(goal.currentValue / goal.targetValue * 100));
  }
  return _clamp(goal.progress.toDouble());
}

/// A category's score is the mean of its goals' scores. All three categories
/// are required, so a category holding no goal scores zero.
Map<GoalCategory, double> scoreCategories(List<ScorableGoal> goals) {
  final scores = <GoalCategory, double>{};
  for (final key in GoalCategory.values) {
    final values = goals
        .where((g) => g.category == key)
        .map(scoreGoal)
        .whereType<double>()
        .toList();
    scores[key] = values.isEmpty
        ? 0
        : _round1(values.reduce((a, b) => a + b) / values.length);
  }
  return scores;
}

/// The Goal Total Score: the three categories combined, equally weighted, so
/// neglecting contribution cannot be papered over by a strong professional.
double weightGoalScore(Map<GoalCategory, double> categories) => _round1(
      GoalCategory.values.fold(
        0.0,
        (sum, key) => sum + (categories[key] ?? 0) * goalCategoryWeight,
      ),
    );

// ---------------------------------------------------------------------------
// Streaks
// ---------------------------------------------------------------------------

/// A day is "kept" when the user showed up at all. The current streak may
/// end today OR yesterday — without that grace every streak would reset at
/// midnight and claw its way back as people got to their tasks.
({int current, int longest}) computeStreaks(
    Set<String> keptDays, DateTime asOf) {
  final end = dayKey(asOf);

  var cursor = keptDays.contains(isoDay(end)) ? end : addDays(end, -1);
  var current = 0;
  while (keptDays.contains(isoDay(cursor))) {
    current += 1;
    cursor = addDays(cursor, -1);
  }

  final sorted = keptDays.toList()..sort();
  var longest = 0;
  var run = 0;
  String? previous;
  for (final day in sorted) {
    final isConsecutive =
        previous != null && isoDay(addDays(parseDayKey(previous), 1)) == day;
    run = isConsecutive ? run + 1 : 1;
    longest = math.max(longest, run);
    previous = day;
  }

  return (current: current, longest: math.max(longest, current));
}

// ---------------------------------------------------------------------------
// User scoring — pure composition over pre-fetched rows
// ---------------------------------------------------------------------------

class UserScoreInputs {
  const UserScoreInputs({
    required this.userId,
    required this.joinedAt,
    required this.goals,
    required this.completionDays,
    required this.checkInDays,
    required this.activeCoreTaskCount,
  });

  final String userId;
  final DateTime joinedAt;
  final List<ScorableGoal> goals;

  /// One isoDay string per core-task completion row (duplicates expected —
  /// one per task per day).
  final List<String> completionDays;

  /// One isoDay string per filed check-in (unique per day).
  final List<String> checkInDays;

  /// Active core tasks in the user's company — the expected daily count.
  final int activeCoreTaskCount;
}

class UserScore {
  const UserScore({
    required this.userId,
    required this.categories,
    required this.goalScore,
    required this.coreTaskScore,
    required this.consistencyScore,
    required this.overallScore,
    required this.currentStreak,
    required this.longestStreak,
    required this.goalsTotal,
    required this.goalsCompleted,
    required this.taskCompletionRate,
    required this.checkInRate,
  });

  factory UserScore.empty(String userId) => UserScore(
        userId: userId,
        categories: {for (final c in GoalCategory.values) c: 0.0},
        goalScore: 0,
        coreTaskScore: 0,
        consistencyScore: 0,
        overallScore: 0,
        currentStreak: 0,
        longestStreak: 0,
        goalsTotal: 0,
        goalsCompleted: 0,
        taskCompletionRate: 0,
        checkInRate: 0,
      );

  final String userId;
  final Map<GoalCategory, double> categories;
  final double goalScore;
  final double coreTaskScore;
  final double consistencyScore;
  final double overallScore;
  final int currentStreak;
  final int longestStreak;
  final int goalsTotal;
  final int goalsCompleted;
  final double taskCompletionRate;
  final double checkInRate;
}

UserScore computeUserScore(UserScoreInputs inputs, {DateTime? asOf}) {
  final end = dayKey(asOf ?? DateTime.now());
  final window = scoringWindow(scoringWindowDays, inputs.joinedAt, end);

  // --- goals ---
  final categories = scoreCategories(inputs.goals);
  final goalScore = weightGoalScore(categories);

  // --- core tasks (tracked, displayed; zero-weighted in overall) ---
  bool inWindow(String day) {
    final d = parseDayKey(day);
    return !d.isBefore(window.start) && !d.isAfter(window.end);
  }

  final doneInWindow = inputs.completionDays.where(inWindow).length;
  final expected = inputs.activeCoreTaskCount * window.days;
  final taskCompletionRate =
      expected > 0 ? _clamp(doneInWindow / expected * 100) : 0.0;

  // --- consistency (tracked, displayed; zero-weighted in overall) ---
  final checkInsInWindow = inputs.checkInDays.toSet().where(inWindow).length;
  final checkInRate =
      window.days > 0 ? _clamp(checkInsInWindow / window.days * 100) : 0.0;

  final keptDays = <String>{...inputs.completionDays, ...inputs.checkInDays};
  final streaks = computeStreaks(keptDays, end);
  final streakScore = _clamp(streaks.current / streakTargetDays, 0, 1) * 100;
  final consistencyScore = _round1(streakScore * consistencyWeightStreak +
      checkInRate * consistencyWeightCheckIns);

  final overallScore = _round1(goalScore * scoreWeightGoals +
      taskCompletionRate * scoreWeightCoreTasks +
      consistencyScore * scoreWeightConsistency);

  return UserScore(
    userId: inputs.userId,
    categories: categories,
    goalScore: goalScore,
    coreTaskScore: _round1(taskCompletionRate),
    consistencyScore: consistencyScore,
    overallScore: overallScore,
    currentStreak: streaks.current,
    longestStreak: streaks.longest,
    goalsTotal: inputs.goals.length,
    goalsCompleted:
        inputs.goals.where((g) => g.status == GoalStatus.completed).length,
    taskCompletionRate: _round1(taskCompletionRate),
    checkInRate: _round1(checkInRate),
  );
}
