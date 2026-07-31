import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_assets.dart';
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

    expect(find.text('WALK 300 KM'), findsOneWidget);
    expect(find.textContaining('60'), findsWidgets); // current value shown
    expect(find.textContaining('300'), findsWidgets); // target shown
    expect(
      find.textContaining('finished by the target date'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, '100');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final data = (await firestore.collection('goals').doc(id).get()).data()!;
    expect((data['currentValue'] as num).toDouble(), 100);
  });

  testWidgets(
      'measure card shows the log-period-target action for a MERIT quest with a period',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'c1'});
    final goalId = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
      targetPeriod: TargetPeriod.weekly,
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: goalId, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Log period target'), findsOneWidget);
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

    await tester.ensureVisible(find.text('Design'));
    await tester.tap(find.text('Design'));
    await tester.pumpAndSettle();

    final plans =
        await firestore.collection('goals').doc(id).collection('tasks').get();
    expect(plans.docs.first.data()['status'], 'IN_PROGRESS');
  });
  testWidgets('quest detail carries the ambient backdrop plate', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final goalId = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: goalId, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    final assetNames = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((provider) => provider.assetName)
        .toSet();

    expect(assetNames, contains(abundanceBackdropAsset));
  });
}
