import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/coach/coach_quests_roster_screen.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_detail_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

class _FakeGoalsService extends GoalsService {
  _FakeGoalsService(this._roster) : super(null);
  final List<CoachMenteeGoals> _roster;

  @override
  Future<List<CoachMenteeGoals>> fetchCoachGoalsRoster() async => _roster;
}

/// A fake that additionally stubs every stream [GoalDetailScreen] reads, so
/// navigating into it during a test never falls back to the real
/// [GoalsService]'s network-polling `_poll` — which schedules a real `Timer`
/// that flutter_test flags as "still pending" at teardown. Every override
/// below returns an already-resolved [Stream.value], so the destination
/// screen renders instantly with no dangling async work.
class _NavFakeGoalsService extends GoalsService {
  _NavFakeGoalsService(this._roster, this._goal) : super(null);
  final List<CoachMenteeGoals> _roster;
  final GoalSummary _goal;

  @override
  Future<List<CoachMenteeGoals>> fetchCoachGoalsRoster() async => _roster;

  @override
  Stream<GoalSummary?> watchGoal(String goalId) => Stream.value(_goal);

  @override
  Stream<List<ActionPlanItem>> watchPlans(String goalId) =>
      Stream.value(const <ActionPlanItem>[]);

  @override
  Stream<List<GoalCommentItem>> watchComments(String goalId) =>
      Stream.value(const <GoalCommentItem>[]);

  @override
  Stream<List<GoalUpdateEntry>> watchUpdates(String goalId) =>
      Stream.value(const <GoalUpdateEntry>[]);
}

void main() {
  testWidgets('roster groups quests by mentee, with an empty state for coaches with none',
      (tester) async {
    final service = _FakeGoalsService(const [
      CoachMenteeGoals(menteeId: '1', menteeName: 'Maychell Alcorin', goals: []),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Maychell Alcorin'), findsOneWidget);
  });

  testWidgets('shows an empty state when the coach has no mentees', (tester) async {
    final service = _FakeGoalsService(const []);

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No students yet'), findsOneWidget);
  });

  testWidgets('a mentee with no quests yet shows a per-mentee empty note, not a crash',
      (tester) async {
    final service = _FakeGoalsService(const [
      CoachMenteeGoals(menteeId: '1', menteeName: 'Maychell Alcorin', goals: []),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No quests set yet'), findsOneWidget);
  });

  testWidgets('search filters the roster by mentee name, client-side',
      (tester) async {
    final service = _FakeGoalsService(const [
      CoachMenteeGoals(menteeId: '1', menteeName: 'Maychell Alcorin', goals: []),
      CoachMenteeGoals(menteeId: '2', menteeName: 'Jamie Rivera', goals: []),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Maychell Alcorin'), findsOneWidget);
    expect(find.text('Jamie Rivera'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'jamie');
    await tester.pumpAndSettle();

    expect(find.text('Maychell Alcorin'), findsNothing);
    expect(find.text('Jamie Rivera'), findsOneWidget);
  });

  testWidgets(
      'tapping a quest opens GoalDetailScreen for the mentee, not the coach',
      (tester) async {
    final goal = GoalSummary(
      id: 'goal-1',
      userId: 'mentee-1',
      companyId: 'abu',
      title: 'Read 12 books',
      description: null,
      notes: null,
      status: GoalStatus.inProgress,
      progress: 40,
      category: GoalCategory.personal,
      goalType: GoalType.merit,
      targetPeriod: TargetPeriod.none,
      direction: GoalDirection.gain,
      targetValue: 12,
      currentValue: 5,
      unit: 'books',
      startDate: DateTime(2026, 1, 1),
      targetDate: DateTime(2026, 12, 31),
      completedAt: null,
    );
    final service = _NavFakeGoalsService(
      [
        CoachMenteeGoals(
          menteeId: 'mentee-1',
          menteeName: 'Jamie Rivera',
          goals: [goal],
        ),
      ],
      goal,
    );

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach-99'),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Read 12 books'));
    await tester.pumpAndSettle();

    final detail = tester.widget<GoalDetailScreen>(find.byType(GoalDetailScreen));
    expect(detail.goalId, 'goal-1');
    // The mentee's uid must be threaded through — never the coach's.
    expect(detail.uid, 'mentee-1');
  });
}
