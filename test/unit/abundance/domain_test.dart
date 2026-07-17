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
