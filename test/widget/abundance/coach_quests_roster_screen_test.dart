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

/// A fake whose roster fetch always fails, plus a call counter so a retry can
/// be observed. Covers the whole-branch review's Important 6: the screen used
/// to branch only on `!snapshot.hasData`, so any failure (network error, 500,
/// the coach-authorization 401 that Critical 2 fixed) rendered an indefinite
/// spinner with no error and no way back.
class _FailingGoalsService extends GoalsService {
  _FailingGoalsService() : super(null);

  int calls = 0;
  bool shouldFail = true;

  @override
  Future<List<CoachMenteeGoals>> fetchCoachGoalsRoster() async {
    calls++;
    if (shouldFail) {
      throw Exception('roster unavailable');
    }
    return const [
      CoachMenteeGoals(menteeId: '1', menteeName: 'Maychell Alcorin', goals: []),
    ];
  }
}

GoalSummary goalIn(GoalCategory category, {String id = 'g'}) {
  return GoalSummary(
    id: id,
    userId: 'mentee-1',
    companyId: 'abu',
    title: 'Goal $id',
    description: null,
    notes: null,
    status: GoalStatus.inProgress,
    progress: 40,
    category: category,
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

  testWidgets(
      'a mentee missing PROFESSIONAL and CONTRIBUTION quests shows both gap badges',
      (tester) async {
    final service = _FakeGoalsService([
      CoachMenteeGoals(
        menteeId: '1',
        menteeName: 'Maychell Alcorin',
        goals: [goalIn(GoalCategory.personal, id: 'g1')],
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No Professional quest'), findsOneWidget);
    expect(find.text('No Contribution quest'), findsOneWidget);
    expect(find.text('No Personal quest'), findsNothing);
  });

  testWidgets(
      'a mentee with a quest in every required category shows no gap badges',
      (tester) async {
    final service = _FakeGoalsService([
      CoachMenteeGoals(
        menteeId: '1',
        menteeName: 'Maychell Alcorin',
        goals: [
          goalIn(GoalCategory.personal, id: 'g1'),
          goalIn(GoalCategory.professional, id: 'g2'),
          goalIn(GoalCategory.contribution, id: 'g3'),
        ],
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No '), findsNothing);
  });
  testWidgets('a failed roster fetch shows an error state with retry, not a spinner',
      (tester) async {
    final service = _FailingGoalsService();

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining("Couldn't load the roster"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(service.calls, 1);
  });

  testWidgets('tapping retry re-attempts the fetch and renders the roster on success',
      (tester) async {
    final service = _FailingGoalsService();

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    service.shouldFail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(service.calls, 2);
    expect(find.text('Maychell Alcorin'), findsOneWidget);
    expect(find.textContaining("Couldn't load the roster"), findsNothing);
  });
}
