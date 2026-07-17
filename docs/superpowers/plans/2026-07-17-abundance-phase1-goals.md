# Abundance Phase 1 — Domain Library + Goals — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port A12-Tracker's pure scoring/domain logic to Dart and ship the Goals feature end-to-end for mentees (hub, detail, form, Firestore service), per the approved spec `docs/superpowers/specs/2026-07-17-a12-tracker-port-design.md`.

**Architecture:** Three layers under `lib/src/features/abundance/`: `domain/` (pure Dart, no Flutter/Firestore imports — day keys, status codes, scoring engine), `services/` (Firestore access; `GoalsService` takes a `FirebaseFirestore` constructor parameter so tests inject `fake_cloud_firestore`), `screens/mentee/` (Flutter UI). Scores are computed live on read; `goals.progress` is a cached mirror of the goal's score, updated on every write that can move it.

**Tech Stack:** Flutter/Dart (package `selfcare_projects`), cloud_firestore ^5.6.2, firebase_auth, fake_cloud_firestore ^3.1.0 (new dev dep), flutter_test.

## Global Constraints

- All commands run from the repo root: `/Users/arlenedacanay/InnerU`.
- Package name is `selfcare_projects` — imports are `package:selfcare_projects/...`.
- `lib/src/features/abundance/domain/` imports ONLY `dart:core`/`dart:math` and sibling domain files. Never Flutter, never Firestore.
- Day keys are LOCAL dates rendered `yyyy-MM-dd` (InnerU convention), NOT UTC (A12 used UTC; we deliberately differ).
- Status/type codes are stored in Firestore as the same TEXT codes A12 uses (`'NOT_STARTED'`, `'MERIT'`, …); enums narrow unknown codes to a fallback, never throw.
- Scoring constants (A12 parity): `SCORE_WEIGHTS = {goals: 1.0, coreTasks: 0.0, consistency: 0.0}`; category weight 1/3 each; scoring window 30 days; consistency = 60% streak + 40% check-in rate; streak saturates at 30 days; plan status weights NOT_STARTED 0 / IN_PROGRESS 50 / DONE 100.
- Rounding: scores round to 1 decimal (`(n*10).round()/10`); the `progress` mirror is a whole int 0–100.
- Do not modify the existing userpoints leaderboard, personal notes, or any screen except the two integration points named in Task 7 (`lib/main.dart` route map, dashboard Overview card).
- Commit after every task. End every commit message with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Disk is tight on this Mac. If any command fails with ENOSPC, stop and report; do not delete anything to make room.

---

### Task 1: Day-key helpers (`domain/day_keys.dart`)

**Files:**
- Create: `lib/src/features/abundance/domain/day_keys.dart`
- Test: `test/unit/abundance/day_keys_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart).
- Produces (used by Tasks 2–6):
  - `DateTime dayKey(DateTime date)` — local midnight of that day
  - `DateTime today()`
  - `DateTime addDays(DateTime date, int days)` — DST-safe
  - `int daysBetween(DateTime from, DateTime to)` — whole days, negative allowed
  - `String isoDay(DateTime date)` — `yyyy-MM-dd`
  - `DateTime parseDayKey(String key)`
  - `List<DateTime> lastNDays(int n, [DateTime? end])` — oldest first, last entry = end's day
  - `typedef ScoringWindow = ({DateTime start, DateTime end, int days})`
  - `ScoringWindow scoringWindow(int windowDays, DateTime joinedAt, [DateTime? end])`
  - `int daysUntil(DateTime target, {DateTime? now})` — negative when overdue

- [ ] **Step 1: Write the failing test**

Create `test/unit/abundance/day_keys_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/day_keys.dart';

void main() {
  test('dayKey buckets to local midnight', () {
    final d = DateTime(2026, 7, 17, 23, 59, 58);
    expect(dayKey(d), DateTime(2026, 7, 17));
  });

  test('isoDay pads month and day', () {
    expect(isoDay(DateTime(2026, 3, 5, 14, 30)), '2026-03-05');
  });

  test('parseDayKey round-trips isoDay', () {
    expect(parseDayKey('2026-03-05'), DateTime(2026, 3, 5));
  });

  test('addDays crosses month boundaries', () {
    expect(addDays(DateTime(2026, 1, 30), 3), DateTime(2026, 2, 2));
    expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
  });

  test('daysBetween buckets both ends and can be negative', () {
    expect(daysBetween(DateTime(2026, 7, 1, 23), DateTime(2026, 7, 3, 1)), 2);
    expect(daysBetween(DateTime(2026, 7, 3), DateTime(2026, 7, 1)), -2);
  });

  test('lastNDays yields n entries oldest first ending on end day', () {
    final days = lastNDays(3, DateTime(2026, 7, 17, 8));
    expect(days, [
      DateTime(2026, 7, 15),
      DateTime(2026, 7, 16),
      DateTime(2026, 7, 17),
    ]);
  });

  test('scoringWindow clamps to join date', () {
    final w = scoringWindow(30, DateTime(2026, 7, 10), DateTime(2026, 7, 17));
    expect(w.start, DateTime(2026, 7, 10));
    expect(w.end, DateTime(2026, 7, 17));
    expect(w.days, 8);
  });

  test('scoringWindow uses full window when join is old', () {
    final w = scoringWindow(30, DateTime(2025, 1, 1), DateTime(2026, 7, 17));
    expect(w.start, DateTime(2026, 6, 18));
    expect(w.days, 30);
  });

  test('daysUntil is negative when overdue', () {
    expect(
      daysUntil(DateTime(2026, 7, 15), now: DateTime(2026, 7, 17)),
      -2,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/abundance/day_keys_test.dart`
Expected: FAIL — cannot resolve `package:selfcare_projects/src/features/abundance/domain/day_keys.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/src/features/abundance/domain/day_keys.dart`:

```dart
/// Every daily record in the abundance feature — a merit log, a completion,
/// a snapshot — is keyed to a "day key": the LOCAL calendar date rendered
/// `yyyy-MM-dd`, matching how the rest of InnerU keys daily records.
/// (A12-Tracker used UTC buckets; on a phone the user's own midnight is the
/// day boundary that matters.)
library;

/// Local midnight of the day [date] falls on.
DateTime dayKey(DateTime date) => DateTime(date.year, date.month, date.day);

/// Today's local midnight.
DateTime today() => dayKey(DateTime.now());

/// [days] whole days after [date]'s day. The constructor normalises
/// overflow, so this is safe across month ends and DST transitions.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Whole days from [from] to [to]; both are bucketed first. Negative when
/// [to] is earlier. Rounded via hours so a DST-shortened day still counts
/// as one day.
int daysBetween(DateTime from, DateTime to) {
  final hours = dayKey(to).difference(dayKey(from)).inHours;
  return (hours / 24).round();
}

/// Stable `yyyy-MM-dd` key — used as Firestore doc-id fragments and for
/// lexicographic date comparison.
String isoDay(DateTime date) {
  final d = dayKey(date);
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

/// Inverse of [isoDay]. `DateTime.parse` of a date-only string is local.
DateTime parseDayKey(String key) => dayKey(DateTime.parse(key));

/// The inclusive list of day keys in a window ending on [end]'s day.
/// `lastNDays(30)` yields 30 entries, oldest first, the last being today.
List<DateTime> lastNDays(int n, [DateTime? end]) {
  final last = dayKey(end ?? DateTime.now());
  return List.generate(n, (i) => addDays(last, i - (n - 1)));
}

/// The window a trailing-N-day metric covers, clamped so it never predates
/// the user joining.
typedef ScoringWindow = ({DateTime start, DateTime end, int days});

ScoringWindow scoringWindow(int windowDays, DateTime joinedAt,
    [DateTime? end]) {
  final endKey = dayKey(end ?? DateTime.now());
  final naiveStart = addDays(endKey, -(windowDays - 1));
  final joinKey = dayKey(joinedAt);
  final start = joinKey.isAfter(naiveStart) ? joinKey : naiveStart;
  return (start: start, end: endKey, days: daysBetween(start, endKey) + 1);
}

/// Negative when overdue. Drives goal-deadline badges.
int daysUntil(DateTime target, {DateTime? now}) =>
    daysBetween(now ?? DateTime.now(), target);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/abundance/day_keys_test.dart`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/abundance/domain/day_keys.dart test/unit/abundance/day_keys_test.dart
git commit -m "feat(abundance): local day-key helpers for the A12 port

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Domain codes and constants (`domain/domain.dart`)

**Files:**
- Create: `lib/src/features/abundance/domain/domain.dart`
- Test: `test/unit/abundance/domain_test.dart`

**Interfaces:**
- Consumes: `day_keys.dart` (Task 1): `dayKey`, `addDays`, `isoDay`.
- Produces (used by Tasks 3–9):
  - Enums (each with `String code`, `String label`, and a static `fromCode(String?)` that falls back, never throws):
    - `GoalCategory { personal, professional, contribution }` — also `int accent` (ARGB int for UI tinting)
    - `GoalStatus { notStarted, inProgress, atRisk, completed, abandoned }`
    - `GoalType { merit, milestone }`
    - `GoalDirection { gain, lose }`
    - `ActionPlanStatus { notStarted, inProgress, done }` — also `int weight` (0/50/100) and `ActionPlanStatus get next` (cycles notStarted → inProgress → done → notStarted)
    - `TargetPeriod { none, daily, every2, every3, every4, every5, every6, weekly }` — also `int days` (0/1/2/3/4/5/6/7)
  - `const openGoalStatuses` — `[notStarted, inProgress, atRisk]`
  - Scoring constants: `scoreWeightGoals = 1.0`, `scoreWeightCoreTasks = 0.0`, `scoreWeightConsistency = 0.0`, `goalCategoryWeight = 1 / 3`, `scoringWindowDays = 30`, `consistencyWeightStreak = 0.6`, `consistencyWeightCheckIns = 0.4`, `streakTargetDays = 30`
  - `class GoalRank { String key; String name; int min; int max; }` and `GoalRank rankForPercent(num percent)`
  - `int periodsRemaining(int daysRemaining, int periodDays)`
  - `double perPeriodTarget(double target, double current, int daysRemaining, int periodDays)`
  - `bool periodLogged(Iterable<String> logDays, TargetPeriod period, {DateTime? asOf})`

- [ ] **Step 1: Write the failing test**

Create `test/unit/abundance/domain_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';

void main() {
  test('fromCode narrows unknown codes to fallbacks', () {
    expect(GoalStatus.fromCode('garbage'), GoalStatus.notStarted);
    expect(GoalStatus.fromCode(null), GoalStatus.notStarted);
    expect(GoalStatus.fromCode('AT_RISK'), GoalStatus.atRisk);
    expect(GoalType.fromCode('junk'), GoalType.merit);
    expect(GoalCategory.fromCode('CONTRIBUTION'), GoalCategory.contribution);
    expect(GoalCategory.fromCode('nope'), GoalCategory.personal);
    expect(TargetPeriod.fromCode('EVERY_3'), TargetPeriod.every3);
    expect(ActionPlanStatus.fromCode('DONE'), ActionPlanStatus.done);
  });

  test('action plan statuses carry A12 weights and cycle', () {
    expect(ActionPlanStatus.notStarted.weight, 0);
    expect(ActionPlanStatus.inProgress.weight, 50);
    expect(ActionPlanStatus.done.weight, 100);
    expect(ActionPlanStatus.notStarted.next, ActionPlanStatus.inProgress);
    expect(ActionPlanStatus.done.next, ActionPlanStatus.notStarted);
  });

  test('score weights match current A12: goals carry everything', () {
    expect(scoreWeightGoals, 1.0);
    expect(scoreWeightCoreTasks, 0.0);
    expect(scoreWeightConsistency, 0.0);
  });

  test('rankForPercent maps 10-point bands, clamped', () {
    expect(rankForPercent(0).name, 'Herald');
    expect(rankForPercent(9.9).name, 'Herald');
    expect(rankForPercent(65).name, 'Divine');
    expect(rankForPercent(65).min, 60);
    expect(rankForPercent(65).max, 70);
    expect(rankForPercent(100).name, 'Titan');
    expect(rankForPercent(100).max, 100);
    expect(rankForPercent(-5).name, 'Herald');
    expect(rankForPercent(250).name, 'Titan');
  });

  test('periodsRemaining floors but never below one', () {
    expect(periodsRemaining(30, 7), 4);
    expect(periodsRemaining(3, 7), 1);
    expect(periodsRemaining(30, 0), 0);
  });

  test('perPeriodTarget spreads the remaining gap', () {
    // 100 target, 20 done, 30 days left, weekly → 80 over 4 periods.
    expect(perPeriodTarget(100, 20, 30, 7), 20.0);
    // Already past target → 0 to log.
    expect(perPeriodTarget(100, 120, 30, 7), 0.0);
    // Rounds to 2 decimals.
    expect(perPeriodTarget(100, 0, 30, 7), 25.0);
    expect(perPeriodTarget(10, 0, 20, 3), 1.67);
  });

  test('periodLogged checks the trailing period window', () {
    final asOf = DateTime(2026, 7, 17);
    expect(
      periodLogged(['2026-07-17'], TargetPeriod.daily, asOf: asOf),
      isTrue,
    );
    expect(
      periodLogged(['2026-07-16'], TargetPeriod.daily, asOf: asOf),
      isFalse,
    );
    // Weekly window reaches back 6 days.
    expect(
      periodLogged(['2026-07-11'], TargetPeriod.weekly, asOf: asOf),
      isTrue,
    );
    expect(
      periodLogged(['2026-07-10'], TargetPeriod.weekly, asOf: asOf),
      isFalse,
    );
    expect(periodLogged(['2026-07-17'], TargetPeriod.none), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/abundance/domain_test.dart`
Expected: FAIL — `domain.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/src/features/abundance/domain/domain.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/abundance/domain_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/abundance/domain/domain.dart test/unit/abundance/domain_test.dart
git commit -m "feat(abundance): domain codes, constants, ranks, merit pacing

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Scoring engine (`domain/scoring.dart`)

**Files:**
- Create: `lib/src/features/abundance/domain/scoring.dart`
- Test: `test/unit/abundance/scoring_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2 (`day_keys.dart`, `domain.dart`).
- Produces (used by Tasks 4–9 and by Phase 3's Firestore fetch layer):
  - `class ScorableGoal { GoalStatus status; int progress; GoalCategory category; GoalType goalType; double targetValue; double currentValue; List<ActionPlanStatus> planStatuses; }` (const ctor, all named, `planStatuses` defaults `const []`)
  - `double? scoreGoal(ScorableGoal goal)` — null means withdrawn (ABANDONED)
  - `Map<GoalCategory, double> scoreCategories(List<ScorableGoal> goals)`
  - `double weightGoalScore(Map<GoalCategory, double> categories)`
  - `({int current, int longest}) computeStreaks(Set<String> keptDays, DateTime asOf)` — keptDays are isoDay strings
  - `class UserScoreInputs { String userId; DateTime joinedAt; List<ScorableGoal> goals; List<String> completionDays; List<String> checkInDays; int activeCoreTaskCount; }` (const ctor, all named)
  - `class UserScore { String userId; Map<GoalCategory, double> categories; double goalScore; double coreTaskScore; double consistencyScore; double overallScore; int currentStreak; int longestStreak; int goalsTotal; int goalsCompleted; double taskCompletionRate; double checkInRate; }` plus `factory UserScore.empty(String userId)`
  - `UserScore computeUserScore(UserScoreInputs inputs, {DateTime? asOf})`

- [ ] **Step 1: Write the failing test**

Create `test/unit/abundance/scoring_test.dart`:

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/abundance/scoring_test.dart`
Expected: FAIL — `scoring.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/src/features/abundance/domain/scoring.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/abundance/scoring_test.dart`
Expected: PASS (11 tests).

- [ ] **Step 5: Run all abundance unit tests together**

Run: `flutter test test/unit/abundance/`
Expected: PASS (all tests from Tasks 1–3).

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/abundance/domain/scoring.dart test/unit/abundance/scoring_test.dart
git commit -m "feat(abundance): pure scoring engine ported from A12 scoring.ts

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Goals service — models, create, watch (`services/goals_service.dart`)

**Files:**
- Modify: `pubspec.yaml` (add `fake_cloud_firestore: ^3.1.0` under `dev_dependencies:`)
- Create: `lib/src/features/abundance/services/goals_service.dart`
- Test: `test/unit/abundance/goals_service_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3 domain exports.
- Produces (used by Tasks 5–9):
  - `class GoalsService { GoalsService(FirebaseFirestore firestore); ... }`
  - `Future<String> createGoal({required String uid, required GoalCategory category, required String title, String? description, String? notes, required DateTime targetDate, GoalType goalType = GoalType.merit, GoalDirection direction = GoalDirection.gain, double targetValue = 0, double currentValue = 0, String unit = '', TargetPeriod targetPeriod = TargetPeriod.none, List<String> planTitles = const []})`
  - `Stream<List<GoalSummary>> watchGoals(String uid)` — sorted by targetDate ascending
  - `Stream<GoalSummary?> watchGoal(String goalId)`
  - `class GoalSummary` with fields `id, userId, companyId, title, description, notes, status (GoalStatus), progress (int), category (GoalCategory), goalType (GoalType), targetPeriod (TargetPeriod), direction (GoalDirection), targetValue (double), currentValue (double), unit (String), startDate (DateTime), targetDate (DateTime), completedAt (DateTime?)` and getters `double? score`, `GoalRank rank`, `int daysUntilDue`, `bool isOverdue`, `double periodTarget`, plus `factory GoalSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc)`
  - `List<GoalCategory> requiredGoalGaps(List<GoalSummary> goals)` — top-level pure function

**Firestore document shape (collection `goals`):** `userId, companyId, category, title, description, notes, status, progress (int), goalType, direction, targetValue (num), currentValue (num), unit, targetPeriod, startDate (Timestamp), targetDate (Timestamp), completedAt (Timestamp?), createdAt, updatedAt (server timestamps)`. Subcollection `tasks`: `title, status, isComplete, dueDate (Timestamp?), completedAt (Timestamp?), sortOrder (int), weight (int)`.

- [ ] **Step 1: Add the test dependency**

In `pubspec.yaml`, inside the existing `dev_dependencies:` block (after `fake_async: ^1.3.1`), add:

```yaml
  fake_cloud_firestore: ^3.1.0
```

Run: `flutter pub get`
Expected: resolves without errors.

- [ ] **Step 2: Write the failing test**

Create `test/unit/abundance/goals_service_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late GoalsService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({
      'activeCompanyId': 'A12',
      'companyId': 'A12',
    });
  });

  test('createGoal writes the goal doc with mirrored progress', () async {
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 25,
      unit: 'km',
      targetPeriod: TargetPeriod.weekly,
    );

    final doc = await firestore.collection('goals').doc(id).get();
    final data = doc.data()!;
    expect(data['userId'], 'u1');
    expect(data['companyId'], 'A12');
    expect(data['category'], 'PERSONAL');
    expect(data['status'], 'NOT_STARTED');
    expect(data['goalType'], 'MERIT');
    expect(data['progress'], 25);
  });

  test('createGoal for milestone zeroes the measure and creates plans',
      () async {
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.professional,
      title: 'Ship the app',
      targetDate: DateTime(2026, 12, 1),
      goalType: GoalType.milestone,
      targetValue: 999, // must be ignored for milestones
      planTitles: ['Design', '  Build  ', ''],
    );

    final data = (await firestore.collection('goals').doc(id).get()).data()!;
    expect(data['targetValue'], 0);
    expect(data['targetPeriod'], 'NONE');
    expect(data['progress'], 0);

    final plans = await firestore
        .collection('goals')
        .doc(id)
        .collection('tasks')
        .get();
    expect(plans.docs.length, 2); // blank title dropped
    final titles = plans.docs.map((d) => d.data()['title']).toSet();
    expect(titles, {'Design', 'Build'});
  });

  test('watchGoals emits summaries sorted by target date', () async {
    await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Later goal',
      targetDate: DateTime(2026, 12, 1),
    );
    await service.createGoal(
      uid: 'u1',
      category: GoalCategory.contribution,
      title: 'Sooner goal',
      targetDate: DateTime(2026, 8, 1),
    );
    // Another user's goal must not leak in.
    await firestore.collection('users').doc('u2').set({'companyId': 'A12'});
    await service.createGoal(
      uid: 'u2',
      category: GoalCategory.personal,
      title: 'Not mine',
      targetDate: DateTime(2026, 8, 1),
    );

    final goals = await service.watchGoals('u1').first;
    expect(goals.map((g) => g.title).toList(), ['Sooner goal', 'Later goal']);
    expect(goals.first.category, GoalCategory.contribution);
  });

  test('GoalSummary derives score, rank, and overdue', () async {
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Read 12 books',
      targetDate: DateTime(2020, 1, 1), // long past → overdue
      targetValue: 12,
      currentValue: 6,
    );
    final summary = await service.watchGoal(id).first;
    expect(summary, isNotNull);
    expect(summary!.score, 50.0);
    expect(summary.rank.name, 'Ancient'); // 50–60 band
    expect(summary.isOverdue, isTrue);
  });

  test('requiredGoalGaps names categories with no live goal', () async {
    await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Something',
      targetDate: DateTime(2026, 9, 1),
    );
    final goals = await service.watchGoals('u1').first;
    expect(requiredGoalGaps(goals),
        [GoalCategory.professional, GoalCategory.contribution]);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/unit/abundance/goals_service_test.dart`
Expected: FAIL — `goals_service.dart` does not exist.

- [ ] **Step 4: Write the implementation**

Create `lib/src/features/abundance/services/goals_service.dart`:

```dart
/// Firestore access for the Goals feature — a port of A12-Tracker's
/// `src/server/goals.ts` write rules onto Firestore. Screens never touch
/// Firestore directly; they go through this service. The Firestore instance
/// is injected so tests can pass a FakeFirebaseFirestore.
library;

import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/day_keys.dart';
import '../domain/domain.dart';
import '../domain/scoring.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

DateTime? _asDate(Object? v) => v is Timestamp ? v.toDate() : null;

class GoalSummary {
  const GoalSummary({
    required this.id,
    required this.userId,
    required this.companyId,
    required this.title,
    required this.description,
    required this.notes,
    required this.status,
    required this.progress,
    required this.category,
    required this.goalType,
    required this.targetPeriod,
    required this.direction,
    required this.targetValue,
    required this.currentValue,
    required this.unit,
    required this.startDate,
    required this.targetDate,
    required this.completedAt,
  });

  factory GoalSummary.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GoalSummary(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      companyId: (data['companyId'] as String?) ?? '',
      title: (data['title'] as String?) ?? '',
      description: data['description'] as String?,
      notes: data['notes'] as String?,
      status: GoalStatus.fromCode(data['status'] as String?),
      progress: (data['progress'] as num?)?.toInt() ?? 0,
      category: GoalCategory.fromCode(data['category'] as String?),
      goalType: GoalType.fromCode(data['goalType'] as String?),
      targetPeriod: TargetPeriod.fromCode(data['targetPeriod'] as String?),
      direction: GoalDirection.fromCode(data['direction'] as String?),
      targetValue: (data['targetValue'] as num?)?.toDouble() ?? 0,
      currentValue: (data['currentValue'] as num?)?.toDouble() ?? 0,
      unit: (data['unit'] as String?) ?? '',
      startDate: _asDate(data['startDate']) ?? DateTime.now(),
      targetDate: _asDate(data['targetDate']) ?? DateTime.now(),
      completedAt: _asDate(data['completedAt']),
    );
  }

  final String id;
  final String userId;
  final String companyId;
  final String title;
  final String? description;
  final String? notes;
  final GoalStatus status;
  final int progress;
  final GoalCategory category;
  final GoalType goalType;
  final TargetPeriod targetPeriod;
  final GoalDirection direction;
  final double targetValue;
  final double currentValue;
  final String unit;
  final DateTime startDate;
  final DateTime targetDate;
  final DateTime? completedAt;

  /// Scored by the same engine that will rank leaderboards. For MILESTONE
  /// goals the stored progress already mirrors plan completion, so the
  /// summary needs no subcollection read.
  double? get score => scoreGoal(ScorableGoal(
        status: status,
        progress: progress,
        category: category,
        goalType: goalType,
        targetValue: targetValue,
        currentValue: currentValue,
      ));

  GoalRank get rank => rankForPercent(progress);

  int get daysUntilDue => daysUntil(targetDate);

  bool get isOverdue =>
      status != GoalStatus.completed &&
      status != GoalStatus.abandoned &&
      daysUntilDue < 0;

  /// A periodic MERIT goal's per-period target; 0 otherwise.
  double get periodTarget =>
      goalType == GoalType.merit && targetPeriod != TargetPeriod.none
          ? perPeriodTarget(
              targetValue, currentValue, daysUntilDue, targetPeriod.days)
          : 0;
}

class ActionPlanItem {
  const ActionPlanItem({
    required this.id,
    required this.title,
    required this.status,
    required this.sortOrder,
    this.dueDate,
    this.completedAt,
  });

  factory ActionPlanItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return ActionPlanItem(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      status: ActionPlanStatus.fromCode(data['status'] as String?),
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      dueDate: _asDate(data['dueDate']),
      completedAt: _asDate(data['completedAt']),
    );
  }

  final String id;
  final String title;
  final ActionPlanStatus status;
  final int sortOrder;
  final DateTime? dueDate;
  final DateTime? completedAt;
}

class GoalUpdateEntry {
  const GoalUpdateEntry({
    required this.id,
    required this.authorId,
    required this.progressFrom,
    required this.progressTo,
    required this.statusFrom,
    required this.statusTo,
    this.note,
    this.createdAt,
  });

  factory GoalUpdateEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GoalUpdateEntry(
      id: doc.id,
      authorId: (data['authorId'] as String?) ?? '',
      progressFrom: (data['progressFrom'] as num?)?.toInt() ?? 0,
      progressTo: (data['progressTo'] as num?)?.toInt() ?? 0,
      statusFrom: GoalStatus.fromCode(data['statusFrom'] as String?),
      statusTo: GoalStatus.fromCode(data['statusTo'] as String?),
      note: data['note'] as String?,
      createdAt: _asDate(data['createdAt']),
    );
  }

  final String id;
  final String authorId;
  final int progressFrom;
  final int progressTo;
  final GoalStatus statusFrom;
  final GoalStatus statusTo;
  final String? note;
  final DateTime? createdAt;
}

class GoalCommentItem {
  const GoalCommentItem({
    required this.id,
    required this.authorId,
    required this.body,
    required this.isPrivate,
    this.createdAt,
  });

  factory GoalCommentItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return GoalCommentItem(
      id: doc.id,
      authorId: (data['authorId'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      isPrivate: data['isPrivate'] == true,
      createdAt: _asDate(data['createdAt']),
    );
  }

  final String id;
  final String authorId;
  final String body;

  /// Private = visible to coaches only (enforced when coach views arrive
  /// in Phase 4; mentees always see their own goals' comments).
  final bool isPrivate;
  final DateTime? createdAt;
}

class MeritLogItem {
  const MeritLogItem({required this.id, required this.date, required this.amount});

  factory MeritLogItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return MeritLogItem(
      id: doc.id,
      date: (data['date'] as String?) ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
    );
  }

  final String id;

  /// isoDay string of the day the merit was logged.
  final String date;
  final double amount;
}

/// The required categories a user has no live goal in. Abandoned goals do
/// not hold a category.
List<GoalCategory> requiredGoalGaps(List<GoalSummary> goals) {
  final held = goals
      .where((g) => g.status != GoalStatus.abandoned)
      .map((g) => g.category)
      .toSet();
  return GoalCategory.values.where((c) => !held.contains(c)).toList();
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class GoalsService {
  GoalsService(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _goals =>
      _firestore.collection('goals');

  /// The stored `progress` mirror must use the same rule `scoreGoal` does,
  /// or the bar and the score would disagree.
  int _measurePct(double targetValue, double currentValue, int fallback) {
    if (targetValue > 0) {
      return ((currentValue / targetValue) * 100).round().clamp(0, 100);
    }
    return fallback.clamp(0, 100);
  }

  /// Informational for MERIT, the score itself for MILESTONE.
  int _planCompletionOf(Iterable<ActionPlanStatus> statuses) {
    final list = statuses.toList();
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (acc, s) => acc + s.weight);
    return (sum / list.length).round();
  }

  Future<String> _activeCompanyId(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data() ?? const <String, dynamic>{};
    return (data['activeCompanyId'] as String?) ??
        (data['companyId'] as String?) ??
        '';
  }

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  Stream<List<GoalSummary>> watchGoals(String uid) => _goals
          .where('userId', isEqualTo: uid)
          .snapshots()
          .map((snapshot) {
        final goals = snapshot.docs.map(GoalSummary.fromDoc).toList()
          ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
        return goals;
      });

  Stream<GoalSummary?> watchGoal(String goalId) => _goals
      .doc(goalId)
      .snapshots()
      .map((doc) => doc.exists ? GoalSummary.fromDoc(doc) : null);

  Stream<List<ActionPlanItem>> watchPlans(String goalId) => _goals
          .doc(goalId)
          .collection('tasks')
          .snapshots()
          .map((snapshot) {
        final plans = snapshot.docs.map(ActionPlanItem.fromDoc).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return plans;
      });

  Stream<List<GoalUpdateEntry>> watchUpdates(String goalId) => _goals
      .doc(goalId)
      .collection('updates')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(GoalUpdateEntry.fromDoc).toList());

  Stream<List<GoalCommentItem>> watchComments(String goalId) => _goals
      .doc(goalId)
      .collection('comments')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(GoalCommentItem.fromDoc).toList());

  Stream<List<MeritLogItem>> watchMerits(String goalId) => _goals
      .doc(goalId)
      .collection('merits')
      .orderBy('date', descending: true)
      .limit(30)
      .snapshots()
      .map((s) => s.docs.map(MeritLogItem.fromDoc).toList());

  // -------------------------------------------------------------------------
  // Writes
  // -------------------------------------------------------------------------

  Future<String> createGoal({
    required String uid,
    required GoalCategory category,
    required String title,
    String? description,
    String? notes,
    required DateTime targetDate,
    GoalType goalType = GoalType.merit,
    GoalDirection direction = GoalDirection.gain,
    double targetValue = 0,
    double currentValue = 0,
    String unit = '',
    TargetPeriod targetPeriod = TargetPeriod.none,
    List<String> planTitles = const [],
  }) async {
    final companyId = await _activeCompanyId(uid);

    // A milestone goal has no numeric measure — its plans are the score.
    final isMilestone = goalType == GoalType.milestone;
    final tv = isMilestone ? 0.0 : math.max(0.0, targetValue);
    final cv = isMilestone ? 0.0 : math.max(0.0, currentValue);

    final doc = _goals.doc();
    final batch = _firestore.batch();
    batch.set(doc, {
      'userId': uid,
      'companyId': companyId,
      'category': category.code,
      'title': title,
      'description': description,
      'notes': notes,
      'status': GoalStatus.notStarted.code,
      'goalType': goalType.code,
      'direction': (isMilestone ? GoalDirection.gain : direction).code,
      'targetValue': tv,
      'currentValue': cv,
      'unit': isMilestone ? '' : unit.trim(),
      'targetPeriod':
          (isMilestone ? TargetPeriod.none : targetPeriod).code,
      'startDate': Timestamp.fromDate(dayKey(DateTime.now())),
      'targetDate': Timestamp.fromDate(dayKey(targetDate)),
      'completedAt': null,
      'progress': isMilestone ? 0 : _measurePct(tv, cv, 0),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final titles = planTitles
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    for (var i = 0; i < titles.length; i++) {
      batch.set(doc.collection('tasks').doc(), {
        'title': titles[i],
        'status': ActionPlanStatus.notStarted.code,
        'isComplete': false,
        'dueDate': null,
        'completedAt': null,
        'sortOrder': i,
        'weight': 1,
      });
    }

    await batch.commit();
    return doc.id;
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/unit/abundance/goals_service_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/src/features/abundance/services/goals_service.dart test/unit/abundance/goals_service_test.dart
git commit -m "feat(abundance): goals service — models, createGoal, watch streams

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Goals service — update, measure, plans, comments, delete

**Files:**
- Modify: `lib/src/features/abundance/services/goals_service.dart` (append methods inside `GoalsService`)
- Test: `test/unit/abundance/goals_service_writes_test.dart`

**Interfaces:**
- Consumes: Task 4's `GoalsService` and models.
- Produces (used by Tasks 8–9):
  - `Future<void> updateGoal({required String goalId, required String actorId, String? title, String? description, String? notes, GoalStatus? status, DateTime? targetDate, GoalDirection? direction, double? targetValue, double? currentValue, String? unit, GoalType? goalType, TargetPeriod? targetPeriod})`
  - `Future<void> setGoalMeasure({required String goalId, required String actorId, required double currentValue})`
  - `Future<String> addActionPlan({required String goalId, required String title})`
  - `Future<void> setActionPlanStatus({required String goalId, required String planId, required ActionPlanStatus status, required String actorId})`
  - `Future<void> deleteActionPlan({required String goalId, required String planId, required String actorId})`
  - `Future<void> addComment({required String goalId, required String authorId, required String body, bool isPrivate = false})`
  - `Future<void> deleteGoal(String goalId)`

- [ ] **Step 1: Write the failing test**

Create `test/unit/abundance/goals_service_writes_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late GoalsService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
  });

  Future<String> meritGoal() => service.createGoal(
        uid: 'u1',
        category: GoalCategory.personal,
        title: 'Save 5000',
        targetDate: DateTime(2026, 12, 31),
        targetValue: 5000,
        currentValue: 1000,
        unit: 'PHP',
      );

  Future<String> milestoneGoal() => service.createGoal(
        uid: 'u1',
        category: GoalCategory.professional,
        title: 'Launch',
        targetDate: DateTime(2026, 12, 31),
        goalType: GoalType.milestone,
        planTitles: ['A', 'B'],
      );

  test('updateGoal completing pins progress to 100 and stamps completedAt',
      () async {
    final id = await meritGoal();
    await service.updateGoal(
      goalId: id,
      actorId: 'u1',
      status: GoalStatus.completed,
    );
    final data = (await firestore.collection('goals').doc(id).get()).data()!;
    expect(data['status'], 'COMPLETED');
    expect(data['progress'], 100);
    expect(data['completedAt'], isNotNull);

    // Reopening clears completedAt and re-mirrors the measure.
    await service.updateGoal(
      goalId: id,
      actorId: 'u1',
      status: GoalStatus.inProgress,
    );
    final after = (await firestore.collection('goals').doc(id).get()).data()!;
    expect(after['completedAt'], isNull);
    expect(after['progress'], 20); // 1000/5000
  });

  test('updateGoal writes a ledger entry', () async {
    final id = await meritGoal();
    await service.updateGoal(
      goalId: id,
      actorId: 'u1',
      currentValue: 2500,
    );
    final updates = await firestore
        .collection('goals')
        .doc(id)
        .collection('updates')
        .get();
    expect(updates.docs.length, 1);
    final entry = updates.docs.first.data();
    expect(entry['progressFrom'], 20);
    expect(entry['progressTo'], 50);
  });

  test('setGoalMeasure re-mirrors the bar', () async {
    final id = await meritGoal();
    await service.setGoalMeasure(goalId: id, actorId: 'u1', currentValue: 4000);
    final data = (await firestore.collection('goals').doc(id).get()).data()!;
    expect(data['currentValue'], 4000);
    expect(data['progress'], 80);
  });

  test('setActionPlanStatus re-mirrors a milestone goal progress', () async {
    final id = await milestoneGoal();
    final plans = await service.watchPlans(id).first;
    await service.setActionPlanStatus(
      goalId: id,
      planId: plans.first.id,
      status: ActionPlanStatus.done,
      actorId: 'u1',
    );
    final data = (await firestore.collection('goals').doc(id).get()).data()!;
    expect(data['progress'], 50); // one DONE of two plans
    final planDoc = await firestore
        .collection('goals')
        .doc(id)
        .collection('tasks')
        .doc(plans.first.id)
        .get();
    expect(planDoc.data()!['isComplete'], true);
  });

  test('addActionPlan appends with next sortOrder; delete re-mirrors',
      () async {
    final id = await milestoneGoal();
    await service.addActionPlan(goalId: id, title: 'C');
    var plans = await service.watchPlans(id).first;
    expect(plans.length, 3);
    expect(plans.last.title, 'C');
    expect(plans.last.sortOrder, 2);

    await service.deleteActionPlan(
        goalId: id, planId: plans.last.id, actorId: 'u1');
    plans = await service.watchPlans(id).first;
    expect(plans.length, 2);
  });

  test('addComment stores body and privacy', () async {
    final id = await meritGoal();
    await service.addComment(
        goalId: id, authorId: 'u1', body: 'On track', isPrivate: false);
    final comments = await service.watchComments(id).first;
    expect(comments.single.body, 'On track');
    expect(comments.single.isPrivate, isFalse);
  });

  test('deleteGoal removes the doc and its subcollections', () async {
    final id = await milestoneGoal();
    await service.addComment(goalId: id, authorId: 'u1', body: 'hi');
    await service.deleteGoal(id);
    expect((await firestore.collection('goals').doc(id).get()).exists, false);
    final plans = await firestore
        .collection('goals')
        .doc(id)
        .collection('tasks')
        .get();
    expect(plans.docs, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/abundance/goals_service_writes_test.dart`
Expected: FAIL — methods not defined on `GoalsService`.

- [ ] **Step 3: Write the implementation**

Append inside the `GoalsService` class in `lib/src/features/abundance/services/goals_service.dart` (after `createGoal`):

```dart
  Future<Map<String, dynamic>> _loadGoalOrThrow(String goalId) async {
    final doc = await _goals.doc(goalId).get();
    final data = doc.data();
    if (data == null) {
      throw StateError('That goal no longer exists.');
    }
    return data;
  }

  Future<void> _addLedgerEntry(
    String goalId, {
    required String authorId,
    required int progressFrom,
    required int progressTo,
    required GoalStatus statusFrom,
    required GoalStatus statusTo,
    String? note,
  }) {
    return _goals.doc(goalId).collection('updates').add({
      'authorId': authorId,
      'progressFrom': progressFrom,
      'progressTo': progressTo,
      'statusFrom': statusFrom.code,
      'statusTo': statusTo.code,
      'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGoal({
    required String goalId,
    required String actorId,
    String? title,
    String? description,
    String? notes,
    GoalStatus? status,
    DateTime? targetDate,
    GoalDirection? direction,
    double? targetValue,
    double? currentValue,
    String? unit,
    GoalType? goalType,
    TargetPeriod? targetPeriod,
  }) async {
    final goal = await _loadGoalOrThrow(goalId);

    final statusFrom = GoalStatus.fromCode(goal['status'] as String?);
    final statusTo = status ?? statusFrom;
    final progressFrom = (goal['progress'] as num?)?.toInt() ?? 0;

    final type = goalType ?? GoalType.fromCode(goal['goalType'] as String?);
    final isMilestone = type == GoalType.milestone;
    final period = isMilestone
        ? TargetPeriod.none
        : (targetPeriod ??
            TargetPeriod.fromCode(goal['targetPeriod'] as String?));
    final tv = isMilestone
        ? 0.0
        : (targetValue != null
            ? math.max(0.0, targetValue)
            : (goal['targetValue'] as num?)?.toDouble() ?? 0);
    final cv = isMilestone
        ? 0.0
        : (currentValue != null
            ? math.max(0.0, currentValue)
            : (goal['currentValue'] as num?)?.toDouble() ?? 0);

    // Progress mirrors the score: the measure for MERIT, plan completion
    // for MILESTONE, pinned to 100 when the goal is marked complete.
    final completing =
        statusTo == GoalStatus.completed && statusFrom != GoalStatus.completed;
    final reopening =
        statusFrom == GoalStatus.completed && statusTo != GoalStatus.completed;
    int progressTo;
    if (statusTo == GoalStatus.completed) {
      progressTo = 100;
    } else if (isMilestone) {
      final plans = await _goals.doc(goalId).collection('tasks').get();
      progressTo = _planCompletionOf(plans.docs
          .map((d) => ActionPlanStatus.fromCode(d.data()['status'] as String?)));
    } else {
      progressTo = _measurePct(tv, cv, progressFrom);
    }

    await _goals.doc(goalId).update({
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (notes != null) 'notes': notes,
      if (targetDate != null) 'targetDate': Timestamp.fromDate(dayKey(targetDate)),
      if (direction != null && !isMilestone) 'direction': direction.code,
      if (unit != null && !isMilestone) 'unit': unit.trim(),
      'goalType': type.code,
      'targetPeriod': period.code,
      'targetValue': tv,
      'currentValue': cv,
      'status': statusTo.code,
      'progress': progressTo,
      if (completing) 'completedAt': Timestamp.fromDate(DateTime.now()),
      if (reopening) 'completedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _addLedgerEntry(
      goalId,
      authorId: actorId,
      progressFrom: progressFrom,
      progressTo: progressTo,
      statusFrom: statusFrom,
      statusTo: statusTo,
    );
  }

  /// Updates just the "current" measure value and re-mirrors the bar.
  Future<void> setGoalMeasure({
    required String goalId,
    required String actorId,
    required double currentValue,
  }) async {
    final goal = await _loadGoalOrThrow(goalId);
    final statusFrom = GoalStatus.fromCode(goal['status'] as String?);
    final progressFrom = (goal['progress'] as num?)?.toInt() ?? 0;
    final current = math.max(0.0, currentValue);
    final progressTo = statusFrom == GoalStatus.completed
        ? 100
        : _measurePct(
            (goal['targetValue'] as num?)?.toDouble() ?? 0,
            current,
            progressFrom,
          );

    await _goals.doc(goalId).update({
      'currentValue': current,
      'progress': progressTo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addLedgerEntry(
      goalId,
      authorId: actorId,
      progressFrom: progressFrom,
      progressTo: progressTo,
      statusFrom: statusFrom,
      statusTo: statusFrom,
    );
  }

  Future<String> addActionPlan({
    required String goalId,
    required String title,
  }) async {
    final existing = await _goals.doc(goalId).collection('tasks').get();
    final doc = await _goals.doc(goalId).collection('tasks').add({
      'title': title.trim(),
      'status': ActionPlanStatus.notStarted.code,
      'isComplete': false,
      'dueDate': null,
      'completedAt': null,
      'sortOrder': existing.docs.length,
      'weight': 1,
    });
    return doc.id;
  }

  /// Re-mirrors a MILESTONE goal's progress after any plan change, unless
  /// the goal is COMPLETED (pinned at 100).
  Future<void> _mirrorMilestoneProgress(String goalId, String actorId) async {
    final goal = await _loadGoalOrThrow(goalId);
    if (GoalType.fromCode(goal['goalType'] as String?) != GoalType.milestone) {
      return;
    }
    final statusNow = GoalStatus.fromCode(goal['status'] as String?);
    if (statusNow == GoalStatus.completed) return;

    final progressFrom = (goal['progress'] as num?)?.toInt() ?? 0;
    final plans = await _goals.doc(goalId).collection('tasks').get();
    final progressTo = _planCompletionOf(plans.docs
        .map((d) => ActionPlanStatus.fromCode(d.data()['status'] as String?)));
    if (progressTo == progressFrom) return;

    await _goals.doc(goalId).update({
      'progress': progressTo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _addLedgerEntry(
      goalId,
      authorId: actorId,
      progressFrom: progressFrom,
      progressTo: progressTo,
      statusFrom: statusNow,
      statusTo: statusNow,
    );
  }

  Future<void> setActionPlanStatus({
    required String goalId,
    required String planId,
    required ActionPlanStatus status,
    required String actorId,
  }) async {
    await _goals.doc(goalId).collection('tasks').doc(planId).update({
      'status': status.code,
      'isComplete': status == ActionPlanStatus.done,
      'completedAt': status == ActionPlanStatus.done
          ? Timestamp.fromDate(DateTime.now())
          : null,
    });
    await _mirrorMilestoneProgress(goalId, actorId);
  }

  Future<void> deleteActionPlan({
    required String goalId,
    required String planId,
    required String actorId,
  }) async {
    await _goals.doc(goalId).collection('tasks').doc(planId).delete();
    await _mirrorMilestoneProgress(goalId, actorId);
  }

  Future<void> addComment({
    required String goalId,
    required String authorId,
    required String body,
    bool isPrivate = false,
  }) {
    return _goals.doc(goalId).collection('comments').add({
      'authorId': authorId,
      'body': body.trim(),
      'isPrivate': isPrivate,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGoal(String goalId) async {
    // Firestore does not cascade-delete subcollections; sweep them first.
    for (final sub in ['tasks', 'updates', 'comments', 'merits']) {
      final docs = await _goals.doc(goalId).collection(sub).get();
      for (final doc in docs.docs) {
        await doc.reference.delete();
      }
    }
    await _goals.doc(goalId).delete();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/abundance/goals_service_writes_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/abundance/services/goals_service.dart test/unit/abundance/goals_service_writes_test.dart
git commit -m "feat(abundance): goal updates, measure, plans, comments, delete

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Goals service — merit logging

**Files:**
- Modify: `lib/src/features/abundance/services/goals_service.dart` (append methods inside `GoalsService`)
- Test: `test/unit/abundance/goals_service_merit_test.dart`

**Interfaces:**
- Consumes: Tasks 4–5.
- Produces (used by Task 9):
  - `Future<void> logMeritTarget({required String goalId, required String actorId})` — logs one period's target; silently no-ops when the period is already logged; throws `StateError` for non-merit or no-cadence goals
  - `Future<void> goExtraMile({required String goalId, required String actorId, required double amount})` — logs a custom amount on top

- [ ] **Step 1: Write the failing test**

Create `test/unit/abundance/goals_service_merit_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late GoalsService service;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
  });

  Future<String> dailyGoal() => service.createGoal(
        uid: 'u1',
        category: GoalCategory.personal,
        title: 'Walk 300 km',
        targetDate: DateTime.now().add(const Duration(days: 30)),
        targetValue: 300,
        currentValue: 0,
        unit: 'km',
        targetPeriod: TargetPeriod.daily,
      );

  test('logMeritTarget adds one period amount and is idempotent per period',
      () async {
    final id = await dailyGoal();
    await service.logMeritTarget(goalId: id, actorId: 'u1');

    var data = (await firestore.collection('goals').doc(id).get()).data()!;
    final afterFirst = (data['currentValue'] as num).toDouble();
    expect(afterFirst, greaterThan(0));

    // Second log in the same period must be a no-op.
    await service.logMeritTarget(goalId: id, actorId: 'u1');
    data = (await firestore.collection('goals').doc(id).get()).data()!;
    expect((data['currentValue'] as num).toDouble(), afterFirst);

    final merits = await service.watchMerits(id).first;
    expect(merits.length, 1);
  });

  test('logMeritTarget rejects goals without a recurring target', () async {
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Hand-tracked',
      targetDate: DateTime(2026, 12, 31),
      targetValue: 10,
    );
    expect(
      () => service.logMeritTarget(goalId: id, actorId: 'u1'),
      throwsStateError,
    );
  });

  test('goExtraMile adds a custom amount and re-mirrors progress', () async {
    final id = await dailyGoal();
    await service.goExtraMile(goalId: id, actorId: 'u1', amount: 150);
    final data = (await firestore.collection('goals').doc(id).get()).data()!;
    expect((data['currentValue'] as num).toDouble(), 150);
    expect(data['progress'], 50);

    // Negative amounts clamp to zero (no un-earning by accident).
    await service.goExtraMile(goalId: id, actorId: 'u1', amount: -50);
    final after = (await firestore.collection('goals').doc(id).get()).data()!;
    expect((after['currentValue'] as num).toDouble(), 150);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/abundance/goals_service_merit_test.dart`
Expected: FAIL — `logMeritTarget` not defined.

- [ ] **Step 3: Write the implementation**

Append inside the `GoalsService` class in `goals_service.dart`:

```dart
  /// One period's contribution to a MERIT goal. Writes the merit log,
  /// advances the current value, and re-mirrors the progress bar — the
  /// goal's currentValue is its starting value plus the sum of its logs.
  Future<void> _addMerit({
    required String goalId,
    required String actorId,
    required double amount,
    required Map<String, dynamic> goal,
  }) async {
    final statusFrom = GoalStatus.fromCode(goal['status'] as String?);
    final progressFrom = (goal['progress'] as num?)?.toInt() ?? 0;
    final current =
        ((goal['currentValue'] as num?)?.toDouble() ?? 0) + amount;
    final progressTo = statusFrom == GoalStatus.completed
        ? 100
        : _measurePct(
            (goal['targetValue'] as num?)?.toDouble() ?? 0,
            current,
            progressFrom,
          );

    final batch = _firestore.batch();
    batch.set(_goals.doc(goalId).collection('merits').doc(), {
      'userId': actorId,
      'date': isoDay(DateTime.now()),
      'amount': amount,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_goals.doc(goalId), {
      'currentValue': current,
      'progress': progressTo,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();

    await _addLedgerEntry(
      goalId,
      authorId: actorId,
      progressFrom: progressFrom,
      progressTo: progressTo,
      statusFrom: statusFrom,
      statusTo: statusFrom,
    );
  }

  /// Logs this period's target amount. A second call within the same period
  /// is a silent no-op, so a double-tap cannot double-log.
  Future<void> logMeritTarget({
    required String goalId,
    required String actorId,
  }) async {
    final goal = await _loadGoalOrThrow(goalId);
    if (GoalType.fromCode(goal['goalType'] as String?) != GoalType.merit) {
      throw StateError('Only a merit goal has a period target to log.');
    }
    final period = TargetPeriod.fromCode(goal['targetPeriod'] as String?);
    if (period == TargetPeriod.none) {
      throw StateError('This goal has no recurring target.');
    }

    final merits = await _goals
        .doc(goalId)
        .collection('merits')
        .orderBy('date', descending: true)
        .limit(10)
        .get();
    final logDays = merits.docs.map((d) => (d.data()['date'] as String?) ?? '');
    if (periodLogged(logDays, period)) return;

    final targetValue = (goal['targetValue'] as num?)?.toDouble() ?? 0;
    final currentValue = (goal['currentValue'] as num?)?.toDouble() ?? 0;
    final targetDate =
        _asDate(goal['targetDate']) ?? addDays(DateTime.now(), 1);
    final amount = perPeriodTarget(
      targetValue,
      currentValue,
      daysUntil(targetDate),
      period.days,
    );
    await _addMerit(
        goalId: goalId, actorId: actorId, amount: amount, goal: goal);
  }

  /// Goes the extra mile: logs a custom amount on top of the period target.
  Future<void> goExtraMile({
    required String goalId,
    required String actorId,
    required double amount,
  }) async {
    final goal = await _loadGoalOrThrow(goalId);
    if (GoalType.fromCode(goal['goalType'] as String?) != GoalType.merit) {
      throw StateError('Only a merit goal can log extra progress.');
    }
    await _addMerit(
      goalId: goalId,
      actorId: actorId,
      amount: math.max(0.0, amount),
      goal: goal,
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/abundance/goals_service_merit_test.dart`
Expected: PASS (3 tests). Then run the whole service suite:
`flutter test test/unit/abundance/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/abundance/services/goals_service.dart test/unit/abundance/goals_service_merit_test.dart
git commit -m "feat(abundance): merit logging — period targets and extra mile

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Goals hub screen + app wiring

**Files:**
- Create: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`
- Modify: `lib/main.dart` (route map + import)
- Modify: `lib/src/features/authentication/screen/dashboard/dashboard_screen.dart` (Overview card)
- Test: `test/widget/abundance/goals_hub_screen_test.dart`

**Interfaces:**
- Consumes: `GoalsService` (Tasks 4–6), domain (Task 2).
- Produces: `class GoalsHubScreen extends StatefulWidget { const GoalsHubScreen({super.key, this.service, this.uid}); }` — `service`/`uid` optional; production resolves them from `FirebaseFirestore.instance` / `FirebaseAuth.instance`, tests inject fakes. Navigates to `GoalFormScreen` (Task 8) and `GoalDetailScreen` (Task 9) — **until those tasks land, keep the two `_openForm`/`_openDetail` methods as the `TODO`-free snackbar placeholders shown below; Tasks 8/9 replace their bodies.**

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/abundance/goals_hub_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goals_hub_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  testWidgets('hub lists the goal and flags missing categories',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalsHubScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Run 100 km'), findsOneWidget);
    // Personal is held; the other two required categories are named as gaps.
    expect(find.textContaining('Professional'), findsWidgets);
    expect(find.textContaining('Contribution'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: FAIL — `goals_hub_screen.dart` does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

/// The mentee's goals hub: one tab per required life category, goal cards
/// with progress bars and rank medals, and a banner naming the categories
/// still missing a goal.
class GoalsHubScreen extends StatefulWidget {
  const GoalsHubScreen({super.key, this.service, this.uid});

  /// Injectable for tests; production falls back to the real instances.
  final GoalsService? service;
  final String? uid;

  @override
  State<GoalsHubScreen> createState() => _GoalsHubScreenState();
}

class _GoalsHubScreenState extends State<GoalsHubScreen> {
  late final GoalsService _service;
  late final String _uid;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? GoalsService(FirebaseFirestore.instance);
    _uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  // Replaced by Task 8 (form) and Task 9 (detail).
  void _openForm({GoalSummary? existing}) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Goal form coming in the next step')),
    );
  }

  void _openDetail(GoalSummary goal) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(goal.title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: GoalCategory.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Goals'),
          bottom: TabBar(
            tabs: [
              for (final category in GoalCategory.values)
                Tab(text: category.label),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openForm(),
          child: const Icon(Icons.add),
        ),
        body: StreamBuilder<List<GoalSummary>>(
          stream: _service.watchGoals(_uid),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final goals = snapshot.data!;
            final gaps = requiredGoalGaps(goals);
            return Column(
              children: [
                if (gaps.isNotEmpty) _GapsBanner(gaps: gaps),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final category in GoalCategory.values)
                        _GoalList(
                          goals: goals
                              .where((g) => g.category == category)
                              .toList(),
                          onTap: _openDetail,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GapsBanner extends StatelessWidget {
  const _GapsBanner({required this.gaps});

  final List<GoalCategory> gaps;

  @override
  Widget build(BuildContext context) {
    final names = gaps.map((g) => g.label).join(' and ');
    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.all(12),
      child: Text(
        'All three areas need a goal — you have none in $names yet. '
        'An empty area scores zero.',
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _GoalList extends StatelessWidget {
  const _GoalList({required this.goals, required this.onTap});

  final List<GoalSummary> goals;
  final void Function(GoalSummary) onTap;

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) {
      return const Center(
        child: Text('No goals here yet. Tap + to set one.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: goals.length,
      itemBuilder: (context, index) => _GoalCard(
        goal: goals[index],
        onTap: () => onTap(goals[index]),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onTap});

  final GoalSummary goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Color(goal.category.accent);
    final due = goal.isOverdue
        ? 'Overdue by ${-goal.daysUntilDue} days'
        : 'Due in ${goal.daysUntilDue} days';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                  Chip(
                    label: Text(goal.status.label,
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: goal.progress / 100,
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${goal.rank.name} · ${goal.progress}%',
                      style: const TextStyle(fontSize: 12)),
                  Text(
                    due,
                    style: TextStyle(
                      fontSize: 12,
                      color: goal.isOverdue ? Colors.red : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the route**

In `lib/main.dart`, add the import alongside the existing screen imports:

```dart
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goals_hub_screen.dart';
```

Then in the `routes:` map, directly below the line
`'/emotionScreen': (context) => _companyThemed(EmotionTrackerPage()),`
add:

```dart
          '/goalsHub': (context) => _companyThemed(const GoalsHubScreen()),
```

- [ ] **Step 6: Add the dashboard entry card**

In `lib/src/features/authentication/screen/dashboard/dashboard_screen.dart`, find the Overview section's second mini card (the "Support" card ending around line 1871). Replace this exact block:

```dart
            Expanded(
              child: _buildMiniOverviewCard(
                icon: CupertinoIcons.chat_bubble_2_fill,
                title: "Support",
                value: "Coach ready",
                accent: const Color(0xFFDCE6D6),
                onTap: () => Navigator.pushNamed(context, '/coachesScreen'),
              ),
            ),
          ],
        ),
```

with:

```dart
            Expanded(
              child: _buildMiniOverviewCard(
                icon: CupertinoIcons.chat_bubble_2_fill,
                title: "Support",
                value: "Coach ready",
                accent: const Color(0xFFDCE6D6),
                onTap: () => Navigator.pushNamed(context, '/coachesScreen'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMiniOverviewCard(
                icon: CupertinoIcons.flag_fill,
                title: "Goals",
                value: "3 life areas",
                accent: const Color(0xFFD6DEE8),
                onTap: () => Navigator.pushNamed(context, '/goalsHub'),
              ),
            ),
          ],
        ),
```

- [ ] **Step 7: Verify the app still analyzes**

Run: `dart analyze lib/src/features/abundance lib/main.dart`
Expected: No errors (info/warnings acceptable if pre-existing).

- [ ] **Step 8: Commit**

```bash
git add lib/src/features/abundance/screens/mentee/goals_hub_screen.dart lib/main.dart lib/src/features/authentication/screen/dashboard/dashboard_screen.dart test/widget/abundance/goals_hub_screen_test.dart
git commit -m "feat(abundance): goals hub screen, route, dashboard entry card

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: Goal form screen (create + edit)

**Files:**
- Create: `lib/src/features/abundance/screens/mentee/goal_form_screen.dart`
- Modify: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` (replace `_openForm` placeholder)
- Test: `test/widget/abundance/goal_form_screen_test.dart`

**Interfaces:**
- Consumes: `GoalsService.createGoal` / `updateGoal` (Tasks 4–5), domain enums.
- Produces: `class GoalFormScreen extends StatefulWidget { const GoalFormScreen({super.key, required this.service, required this.uid, this.existing}); final GoalsService service; final String uid; final GoalSummary? existing; }` — `existing == null` creates; otherwise edits that goal.

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/abundance/goal_form_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  testWidgets('form requires a title and creates a merit goal',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    // Saving with no title trips the validator.
    await tester.tap(find.text('Save goal'));
    await tester.pumpAndSettle();
    expect(find.text('Title is required'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('goal-title')), 'Read 12 books');
    await tester.enterText(find.byKey(const Key('goal-target-value')), '12');
    await tester.tap(find.text('Save goal'));
    await tester.pumpAndSettle();

    final goals = await firestore.collection('goals').get();
    expect(goals.docs.length, 1);
    expect(goals.docs.first.data()['title'], 'Read 12 books');
    expect(goals.docs.first.data()['targetValue'], 12);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/goal_form_screen_test.dart`
Expected: FAIL — `goal_form_screen.dart` does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/src/features/abundance/screens/mentee/goal_form_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/day_keys.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

/// Create or edit a goal. A MERIT goal carries a numeric measure (target,
/// current, unit, optional recurring cadence); a MILESTONE goal is scored by
/// its action plans instead, so the measure fields hide and a plan list
/// shows.
class GoalFormScreen extends StatefulWidget {
  const GoalFormScreen({
    super.key,
    required this.service,
    required this.uid,
    this.existing,
  });

  final GoalsService service;
  final String uid;
  final GoalSummary? existing;

  @override
  State<GoalFormScreen> createState() => _GoalFormScreenState();
}

class _GoalFormScreenState extends State<GoalFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _targetValue;
  late final TextEditingController _currentValue;
  late final TextEditingController _unit;
  final _planEntry = TextEditingController();

  late GoalCategory _category;
  late GoalType _goalType;
  late GoalDirection _direction;
  late TargetPeriod _targetPeriod;
  late DateTime _targetDate;
  final List<String> _planTitles = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _title = TextEditingController(text: g?.title ?? '');
    _description = TextEditingController(text: g?.description ?? '');
    _targetValue = TextEditingController(
        text: g == null || g.targetValue == 0 ? '' : '${g.targetValue}');
    _currentValue = TextEditingController(
        text: g == null || g.currentValue == 0 ? '' : '${g.currentValue}');
    _unit = TextEditingController(text: g?.unit ?? '');
    _category = g?.category ?? GoalCategory.personal;
    _goalType = g?.goalType ?? GoalType.merit;
    _direction = g?.direction ?? GoalDirection.gain;
    _targetPeriod = g?.targetPeriod ?? TargetPeriod.none;
    _targetDate = g?.targetDate ?? addDays(DateTime.now(), 90);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _targetValue.dispose();
    _currentValue.dispose();
    _unit.dispose();
    _planEntry.dispose();
    super.dispose();
  }

  Future<void> _pickTargetDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final targetValue = double.tryParse(_targetValue.text.trim()) ?? 0;
      final currentValue = double.tryParse(_currentValue.text.trim()) ?? 0;
      if (_isEdit) {
        await widget.service.updateGoal(
          goalId: widget.existing!.id,
          actorId: widget.uid,
          title: _title.text.trim(),
          description: _description.text.trim(),
          targetDate: _targetDate,
          goalType: _goalType,
          direction: _direction,
          targetValue: targetValue,
          currentValue: currentValue,
          unit: _unit.text,
          targetPeriod: _targetPeriod,
        );
      } else {
        await widget.service.createGoal(
          uid: widget.uid,
          category: _category,
          title: _title.text.trim(),
          description: _description.text.trim(),
          targetDate: _targetDate,
          goalType: _goalType,
          direction: _direction,
          targetValue: targetValue,
          currentValue: currentValue,
          unit: _unit.text,
          targetPeriod: _targetPeriod,
          planTitles: _planTitles,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save goal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMerit = _goalType == GoalType.merit;
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit goal' : 'New goal')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('goal-title'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            if (!_isEdit)
              DropdownButtonFormField<GoalCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Life area'),
                items: [
                  for (final c in GoalCategory.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _category = v!),
              ),
            const SizedBox(height: 12),
            SegmentedButton<GoalType>(
              segments: [
                for (final t in GoalType.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_goalType},
              onSelectionChanged: (s) => setState(() => _goalType = s.first),
            ),
            const SizedBox(height: 12),
            if (isMerit) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('goal-target-value'),
                      controller: _targetValue,
                      decoration:
                          const InputDecoration(labelText: 'Target value'),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('goal-current-value'),
                      controller: _currentValue,
                      decoration:
                          const InputDecoration(labelText: 'Current value'),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(
                          labelText: 'Unit', hintText: 'km, PHP, books…'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<GoalDirection>(
                      initialValue: _direction,
                      decoration:
                          const InputDecoration(labelText: 'Direction'),
                      items: [
                        for (final d in GoalDirection.values)
                          DropdownMenuItem(value: d, child: Text(d.label)),
                      ],
                      onChanged: (v) => setState(() => _direction = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TargetPeriod>(
                initialValue: _targetPeriod,
                decoration:
                    const InputDecoration(labelText: 'Recurring target'),
                items: [
                  for (final p in TargetPeriod.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: (v) => setState(() => _targetPeriod = v!),
              ),
            ] else if (!_isEdit) ...[
              Text('Action plans',
                  style: Theme.of(context).textTheme.titleSmall),
              for (final title in _planTitles)
                ListTile(
                  dense: true,
                  title: Text(title),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        setState(() => _planTitles.remove(title)),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _planEntry,
                      decoration:
                          const InputDecoration(hintText: 'Add a plan step'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      final t = _planEntry.text.trim();
                      if (t.isEmpty) return;
                      setState(() {
                        _planTitles.add(t);
                        _planEntry.clear();
                      });
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Target date'),
              subtitle: Text(isoDay(_targetDate)),
              trailing: const Icon(Icons.calendar_today, size: 20),
              onTap: _pickTargetDate,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save goal'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Hook the hub to the form**

In `goals_hub_screen.dart`, add the import:

```dart
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
```

and replace the `_openForm` placeholder method body with:

```dart
  void _openForm({GoalSummary? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalFormScreen(
          service: _service,
          uid: _uid,
          existing: existing,
        ),
      ),
    );
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widget/abundance/`
Expected: PASS (hub + form tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/abundance/screens/mentee/goal_form_screen.dart lib/src/features/abundance/screens/mentee/goals_hub_screen.dart test/widget/abundance/goal_form_screen_test.dart
git commit -m "feat(abundance): goal create/edit form

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: Goal detail screen

**Files:**
- Create: `lib/src/features/abundance/screens/mentee/goal_detail_screen.dart`
- Modify: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` (replace `_openDetail` placeholder)
- Test: `test/widget/abundance/goal_detail_screen_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 4–6 and 8.
- Produces: `class GoalDetailScreen extends StatefulWidget { const GoalDetailScreen({super.key, required this.goalId, required this.service, required this.uid}); }`

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/abundance/goal_detail_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_detail_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  testWidgets('detail shows the measure and logs the period target',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Walk 300 km',
      targetDate: DateTime.now().add(const Duration(days: 30)),
      targetValue: 300,
      currentValue: 60,
      unit: 'km',
      targetPeriod: TargetPeriod.daily,
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: id, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Walk 300 km'), findsOneWidget);
    expect(find.textContaining('60'), findsWidgets); // current value shown
    expect(find.textContaining('300'), findsWidgets); // target shown

    await tester.tap(find.byKey(const Key('log-period-target')));
    await tester.pumpAndSettle();

    final data = (await firestore.collection('goals').doc(id).get()).data()!;
    expect((data['currentValue'] as num).toDouble(), greaterThan(60));
  });

  testWidgets('milestone detail cycles a plan status', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.professional,
      title: 'Launch',
      targetDate: DateTime.now().add(const Duration(days: 60)),
      goalType: GoalType.milestone,
      planTitles: ['Design'],
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: id, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Design'));
    await tester.pumpAndSettle();

    final plans =
        await firestore.collection('goals').doc(id).collection('tasks').get();
    expect(plans.docs.first.data()['status'], 'IN_PROGRESS');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/goal_detail_screen_test.dart`
Expected: FAIL — `goal_detail_screen.dart` does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/src/features/abundance/screens/mentee/goal_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

/// One goal, in full: measure panel (MERIT) or informational plan completion
/// (MILESTONE), action plans, status controls, updates ledger, comments.
class GoalDetailScreen extends StatefulWidget {
  const GoalDetailScreen({
    super.key,
    required this.goalId,
    required this.service,
    required this.uid,
  });

  final String goalId;
  final GoalsService service;
  final String uid;

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _setStatus(GoalStatus status) async {
    if (status == GoalStatus.abandoned) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Abandon this goal?'),
          content: const Text(
              'An abandoned goal is withdrawn from your score — it does not '
              'count as zero. You can reopen it later.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Abandon')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await widget.service.updateGoal(
        goalId: widget.goalId, actorId: widget.uid, status: status);
  }

  Future<void> _editCurrentValue(GoalSummary goal) async {
    final controller =
        TextEditingController(text: goal.currentValue.toString());
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Current ${goal.unit.isEmpty ? 'value' : goal.unit}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null) {
      await widget.service.setGoalMeasure(
          goalId: widget.goalId, actorId: widget.uid, currentValue: value);
    }
  }

  Future<void> _goExtraMile() async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go the extra mile'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Amount to add'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text('Log it'),
          ),
        ],
      ),
    );
    if (amount != null && amount > 0) {
      await widget.service.goExtraMile(
          goalId: widget.goalId, actorId: widget.uid, amount: amount);
    }
  }

  Future<void> _deleteGoal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this goal?'),
        content: const Text('This permanently removes the goal, its plans, '
            'updates, and comments.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.service.deleteGoal(widget.goalId);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<GoalSummary?>(
      stream: widget.service.watchGoal(widget.goalId),
      builder: (context, snapshot) {
        final goal = snapshot.data;
        if (goal == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(goal.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GoalFormScreen(
                      service: widget.service,
                      uid: widget.uid,
                      existing: goal,
                    ),
                  ),
                ),
              ),
              PopupMenuButton<GoalStatus>(
                onSelected: _setStatus,
                itemBuilder: (context) => [
                  for (final s in GoalStatus.values)
                    if (s != goal.status)
                      PopupMenuItem(value: s, child: Text(s.label)),
                ],
                icon: const Icon(Icons.flag_outlined),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteGoal,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Header(goal: goal),
              const SizedBox(height: 16),
              if (goal.goalType == GoalType.merit)
                _MeasurePanel(
                  goal: goal,
                  service: widget.service,
                  uid: widget.uid,
                  onEditValue: () => _editCurrentValue(goal),
                  onExtraMile: _goExtraMile,
                ),
              const SizedBox(height: 16),
              _PlansPanel(
                  goalId: widget.goalId,
                  service: widget.service,
                  uid: widget.uid),
              const SizedBox(height: 16),
              _CommentsPanel(
                goalId: widget.goalId,
                service: widget.service,
                uid: widget.uid,
                controller: _commentController,
              ),
              const SizedBox(height: 16),
              _UpdatesPanel(goalId: widget.goalId, service: widget.service),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.goal});

  final GoalSummary goal;

  @override
  Widget build(BuildContext context) {
    final accent = Color(goal.category.accent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Chip(
              label: Text(goal.category.label,
                  style: const TextStyle(fontSize: 11)),
              backgroundColor: accent.withValues(alpha: 0.2),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 8),
            Chip(
              label: Text(goal.status.label,
                  style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if ((goal.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(goal.description!),
        ],
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: goal.progress / 100,
          color: accent,
          backgroundColor: accent.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 6),
        Text(
          '${goal.rank.name} · ${goal.progress}% · '
          '${goal.isOverdue ? "overdue" : "${goal.daysUntilDue} days left"}',
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class _MeasurePanel extends StatelessWidget {
  const _MeasurePanel({
    required this.goal,
    required this.service,
    required this.uid,
    required this.onEditValue,
    required this.onExtraMile,
  });

  final GoalSummary goal;
  final GoalsService service;
  final String uid;
  final VoidCallback onEditValue;
  final VoidCallback onExtraMile;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MeritLogItem>>(
      stream: service.watchMerits(goal.id),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? const <MeritLogItem>[];
        final logged =
            periodLogged(logs.map((l) => l.date), goal.targetPeriod);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Measure', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  '${goal.currentValue} / ${goal.targetValue} ${goal.unit}'
                      .trim(),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                if (goal.targetPeriod != TargetPeriod.none) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${goal.targetPeriod.label}: '
                    '${goal.periodTarget} ${goal.unit}'.trim(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    if (goal.targetPeriod != TargetPeriod.none)
                      FilledButton.tonal(
                        key: const Key('log-period-target'),
                        onPressed: logged
                            ? null
                            : () => service.logMeritTarget(
                                goalId: goal.id, actorId: uid),
                        child: Text(
                            logged ? 'Logged this period' : 'Log period target'),
                      ),
                    OutlinedButton(
                      onPressed: onExtraMile,
                      child: const Text('Go extra mile'),
                    ),
                    TextButton(
                      onPressed: onEditValue,
                      child: const Text('Edit value'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlansPanel extends StatelessWidget {
  const _PlansPanel({
    required this.goalId,
    required this.service,
    required this.uid,
  });

  final String goalId;
  final GoalsService service;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final entry = TextEditingController();
    return StreamBuilder<List<ActionPlanItem>>(
      stream: service.watchPlans(goalId),
      builder: (context, snapshot) {
        final plans = snapshot.data ?? const <ActionPlanItem>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Action plans',
                    style: Theme.of(context).textTheme.titleSmall),
                for (final plan in plans)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      switch (plan.status) {
                        ActionPlanStatus.done => Icons.check_circle,
                        ActionPlanStatus.inProgress => Icons.timelapse,
                        ActionPlanStatus.notStarted =>
                          Icons.radio_button_unchecked,
                      },
                      color: plan.status == ActionPlanStatus.done
                          ? Colors.green
                          : null,
                    ),
                    title: Text(plan.title),
                    subtitle: Text(plan.status.label,
                        style: const TextStyle(fontSize: 11)),
                    onTap: () => service.setActionPlanStatus(
                      goalId: goalId,
                      planId: plan.id,
                      status: plan.status.next,
                      actorId: uid,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => service.deleteActionPlan(
                          goalId: goalId, planId: plan.id, actorId: uid),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: entry,
                        decoration: const InputDecoration(
                            hintText: 'Add a plan step', isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final t = entry.text.trim();
                        if (t.isEmpty) return;
                        service.addActionPlan(goalId: goalId, title: t);
                        entry.clear();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CommentsPanel extends StatelessWidget {
  const _CommentsPanel({
    required this.goalId,
    required this.service,
    required this.uid,
    required this.controller,
  });

  final String goalId;
  final GoalsService service;
  final String uid;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GoalCommentItem>>(
      stream: service.watchComments(goalId),
      builder: (context, snapshot) {
        final comments = snapshot.data ?? const <GoalCommentItem>[];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Comments',
                    style: Theme.of(context).textTheme.titleSmall),
                for (final comment in comments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(comment.body),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                            hintText: 'Add a comment', isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, size: 20),
                      onPressed: () {
                        final body = controller.text.trim();
                        if (body.isEmpty) return;
                        service.addComment(
                            goalId: goalId, authorId: uid, body: body);
                        controller.clear();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UpdatesPanel extends StatelessWidget {
  const _UpdatesPanel({required this.goalId, required this.service});

  final String goalId;
  final GoalsService service;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GoalUpdateEntry>>(
      stream: service.watchUpdates(goalId),
      builder: (context, snapshot) {
        final updates = snapshot.data ?? const <GoalUpdateEntry>[];
        if (updates.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('History', style: Theme.of(context).textTheme.titleSmall),
                for (final update in updates.take(15))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      update.statusFrom != update.statusTo
                          ? '${update.statusFrom.label} → '
                              '${update.statusTo.label} · '
                              '${update.progressFrom}% → ${update.progressTo}%'
                          : '${update.progressFrom}% → ${update.progressTo}%',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Hook the hub to the detail screen**

In `goals_hub_screen.dart`, add the import:

```dart
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_detail_screen.dart';
```

and replace the `_openDetail` placeholder method body with:

```dart
  void _openDetail(GoalSummary goal) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalDetailScreen(
          goalId: goal.id,
          service: _service,
          uid: _uid,
        ),
      ),
    );
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widget/abundance/`
Expected: PASS (all widget tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/abundance/screens/mentee/goal_detail_screen.dart lib/src/features/abundance/screens/mentee/goals_hub_screen.dart test/widget/abundance/goal_detail_screen_test.dart
git commit -m "feat(abundance): goal detail — measure, plans, comments, history

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Full verification

**Files:** none new.

- [ ] **Step 1: Run the entire abundance suite**

Run: `flutter test test/unit/abundance/ test/widget/abundance/`
Expected: ALL PASS. Paste the summary line into the completion report.

- [ ] **Step 2: Run the pre-existing test suite to prove nothing broke**

Run: `flutter test`
Expected: no NEW failures versus the state before this plan (if pre-existing failures exist, list them and confirm they predate the branch by checking out the previous commit is NOT required — compare against the failure list from Task 1's first full run if one was recorded, otherwise note them as pre-existing).

- [ ] **Step 3: Analyze the new code**

Run: `dart analyze lib/src/features/abundance test/unit/abundance test/widget/abundance`
Expected: zero errors.

- [ ] **Step 4: Verify the spec's Phase 1 checklist**

Confirm each item maps to shipped code: domain library (Tasks 1–3), scoring engine with tests (Task 3), goals hub (Task 7), goal detail (Task 9), goal form (Task 8), goals service (Tasks 4–6). Report any gap honestly instead of claiming done.

- [ ] **Step 5: Final commit if any straggler files remain**

```bash
git status --short
# stage only files this plan created/modified, then:
git commit -m "chore(abundance): phase 1 wrap-up

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
