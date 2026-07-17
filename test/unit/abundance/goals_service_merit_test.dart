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
