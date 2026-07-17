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
