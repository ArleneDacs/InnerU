import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  testWidgets('wizard starts on step 1 of 4 and blocks Next until the declaration is filled',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 4 — What'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Still on step 1 — the declaration field is required and empty.
    expect(find.text('Step 1 of 4 — What'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      'I see myself finishing what I start',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4 — How'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('step 2 requires a category and a target value before advancing',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      'I see myself finishing what I start',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // No category chosen yet — Next must not advance.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 — How'), findsOneWidget);

    await tester.tap(find.text('Personal'));
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '10');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 — When & qualities'), findsOneWidget);
  });

  testWidgets(
      'editing an existing quest seeds the declaration field from its title '
      'so step 1 is not blocked by an empty required field',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());
    final existing = GoalSummary(
      id: 'g1',
      userId: 'u1',
      companyId: 'A12',
      title: 'Walk 300 km',
      description: 'Walk 300 km on or before June 1, 2026.',
      notes: null,
      status: GoalStatus.inProgress,
      progress: 0,
      category: GoalCategory.personal,
      goalType: GoalType.merit,
      targetPeriod: TargetPeriod.daily,
      direction: GoalDirection.gain,
      targetValue: 300,
      currentValue: 60,
      unit: 'km',
      startDate: DateTime(2026, 1, 1),
      targetDate: DateTime(2026, 6, 1),
      completedAt: null,
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1', existing: existing),
    ));
    await tester.pumpAndSettle();

    // The declaration field must already contain the quest's title -- not
    // be empty -- so editing doesn't present a misleadingly empty required
    // field on step 0.
    final declarationField = tester.widget<TextField>(
      find.byKey(const Key('quest-declaration-field')),
    );
    expect(declarationField.controller!.text, 'Walk 300 km');

    // Because the field is pre-filled, Next must advance immediately with
    // no typing required.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 — How'), findsOneWidget);
  });
}
