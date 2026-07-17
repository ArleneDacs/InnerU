/// The shared vocabulary of the abundance feature — a Dart port of
/// A12-Tracker's `src/lib/domain.ts`. Firestore stores these codes as TEXT;
/// this module is the single place that narrows TEXT back into enums, and
/// the only place a new status/category code should be added.
library;

import 'dart:math' as math;

import 'day_keys.dart';

// ---------------------------------------------------------------------------
// Goal categories — fixed, all three required. An empty category scores zero
// on purpose: never setting a contribution goal is exactly the gap the score
// exists to surface.
// ---------------------------------------------------------------------------

enum GoalCategory {
  personal('PERSONAL', 'Personal', 0xFF7C9CBF),
  professional('PROFESSIONAL', 'Professional', 0xFF8FBF9F),
  contribution('CONTRIBUTION', 'Contribution', 0xFFBF9B7C);

  const GoalCategory(this.code, this.label, this.accent);
  final String code;
  final String label;

  /// ARGB accent for UI tinting; kept as an int so this file stays
  /// Flutter-free. Screens wrap it: `Color(category.accent)`.
  final int accent;

  static GoalCategory fromCode(String? code) => values.firstWhere(
        (v) => v.code == code,
        orElse: () => GoalCategory.personal,
      );
}

// ---------------------------------------------------------------------------
// Statuses and types
// ---------------------------------------------------------------------------

enum GoalStatus {
  notStarted('NOT_STARTED', 'Not started'),
  inProgress('IN_PROGRESS', 'In progress'),
  atRisk('AT_RISK', 'At risk'),
  completed('COMPLETED', 'Completed'),
  abandoned('ABANDONED', 'Abandoned');

  const GoalStatus(this.code, this.label);
  final String code;
  final String label;

  static GoalStatus fromCode(String? code) => values.firstWhere(
        (v) => v.code == code,
        orElse: () => GoalStatus.notStarted,
      );
}

/// Statuses that still count against a user's active workload.
const openGoalStatuses = [
  GoalStatus.notStarted,
  GoalStatus.inProgress,
  GoalStatus.atRisk,
];

/// MERIT — a numeric measure chipped away over time (current ÷ target).
/// MILESTONE — scored by its action plans instead of a measure.
enum GoalType {
  merit('MERIT', 'Merit'),
  milestone('MILESTONE', 'Milestone');

  const GoalType(this.code, this.label);
  final String code;
  final String label;

  static GoalType fromCode(String? code) => values.firstWhere(
        (v) => v.code == code,
        orElse: () => GoalType.merit,
      );
}

/// Whether the measured metric is being grown or reduced — a display label;
/// the score is current ÷ target either way.
enum GoalDirection {
  gain('GAIN', 'Gain'),
  lose('LOSE', 'Lose');

  const GoalDirection(this.code, this.label);
  final String code;
  final String label;

  static GoalDirection fromCode(String? code) => values.firstWhere(
        (v) => v.code == code,
        orElse: () => GoalDirection.gain,
      );
}

/// An action plan's state. For a MILESTONE goal the average of [weight]
/// across its plans IS the goal score; for a MERIT goal plans are
/// informational only.
enum ActionPlanStatus {
  notStarted('NOT_STARTED', 'Not started', 0),
  inProgress('IN_PROGRESS', 'In progress', 50),
  done('DONE', 'Done', 100);

  const ActionPlanStatus(this.code, this.label, this.weight);
  final String code;
  final String label;
  final int weight;

  /// The status a tap advances to.
  ActionPlanStatus get next => switch (this) {
        ActionPlanStatus.notStarted => ActionPlanStatus.inProgress,
        ActionPlanStatus.inProgress => ActionPlanStatus.done,
        ActionPlanStatus.done => ActionPlanStatus.notStarted,
      };

  static ActionPlanStatus fromCode(String? code) => values.firstWhere(
        (v) => v.code == code,
        orElse: () => ActionPlanStatus.notStarted,
      );
}

/// A MERIT goal's cadence. NONE means the current value is edited by hand.
enum TargetPeriod {
  none('NONE', 'No recurring target', 0),
  daily('DAILY', 'Daily', 1),
  every2('EVERY_2', 'Every 2 days', 2),
  every3('EVERY_3', 'Every 3 days', 3),
  every4('EVERY_4', 'Every 4 days', 4),
  every5('EVERY_5', 'Every 5 days', 5),
  every6('EVERY_6', 'Every 6 days', 6),
  weekly('WEEKLY', 'Weekly', 7);

  const TargetPeriod(this.code, this.label, this.days);
  final String code;
  final String label;
  final int days;

  static TargetPeriod fromCode(String? code) => values.firstWhere(
        (v) => v.code == code,
        orElse: () => TargetPeriod.none,
      );
}

// ---------------------------------------------------------------------------
// Scoring constants — A12 parity. The Overall Score IS the Goal Total Score;
// core tasks and consistency are tracked and shown but carry zero weight.
// Kept as data so the blend can be re-tuned without touching the engine.
// ---------------------------------------------------------------------------

const double scoreWeightGoals = 1.0;
const double scoreWeightCoreTasks = 0.0;
const double scoreWeightConsistency = 0.0;

/// Within the goal score, each category pulls equal weight.
const double goalCategoryWeight = 1 / 3;

/// Trailing-window length for core-task and consistency metrics.
const int scoringWindowDays = 30;

const double consistencyWeightStreak = 0.6;
const double consistencyWeightCheckIns = 0.4;

/// A streak this long saturates the streak half of the consistency score.
const int streakTargetDays = 30;

// ---------------------------------------------------------------------------
// Goal rank medals — one rank per 10-point progress band. Display flavour
// only; never feeds scoring.
// ---------------------------------------------------------------------------

class GoalRank {
  const GoalRank(this.key, this.name, this.min, this.max);
  final String key;
  final String name;
  final int min;
  final int max;
}

const _rankNames = <(String, String)>[
  ('HERALD', 'Herald'),
  ('GUARDIAN', 'Guardian'),
  ('CRUSADER', 'Crusader'),
  ('ARCHON', 'Archon'),
  ('LEGEND', 'Legend'),
  ('ANCIENT', 'Ancient'),
  ('DIVINE', 'Divine'),
  ('IMMORTAL', 'Immortal'),
  ('MASTER_IMMORTAL', 'Master Immortal'),
  ('TITAN', 'Titan'),
];

GoalRank rankForPercent(num percent) {
  final clamped = percent.clamp(0, 100);
  final index = math.min(_rankNames.length - 1, clamped ~/ 10);
  final (key, name) = _rankNames[index];
  final isTop = index == _rankNames.length - 1;
  return GoalRank(key, name, index * 10, isTop ? 100 : index * 10 + 10);
}

// ---------------------------------------------------------------------------
// MERIT pacing
// ---------------------------------------------------------------------------

/// Whole periods of length [periodDays] that fit in [daysRemaining] — at
/// least one, so a target due sooner than a full period still has something
/// to aim at.
int periodsRemaining(int daysRemaining, int periodDays) {
  if (periodDays <= 0) return 0;
  return math.max(1, daysRemaining ~/ periodDays);
}

/// The amount a MERIT goal should log each period to close the gap from
/// [current] to [target] by the target date. Two decimals for a clean label.
double perPeriodTarget(
    double target, double current, int daysRemaining, int periodDays) {
  final periods = periodsRemaining(daysRemaining, periodDays);
  if (periods <= 0) return 0;
  final remaining = math.max(0.0, target - current);
  return (remaining / periods * 100).round() / 100;
}

/// Whether the current period already has a merit log. [logDays] are isoDay
/// strings of existing logs; lexicographic compare works for `yyyy-MM-dd`.
bool periodLogged(Iterable<String> logDays, TargetPeriod period,
    {DateTime? asOf}) {
  if (period == TargetPeriod.none) return false;
  final end = dayKey(asOf ?? DateTime.now());
  final since = isoDay(addDays(end, -(math.max(1, period.days) - 1)));
  return logDays.any((d) => d.compareTo(since) >= 0);
}
