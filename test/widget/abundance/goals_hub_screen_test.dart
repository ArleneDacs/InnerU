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
