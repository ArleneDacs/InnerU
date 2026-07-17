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
