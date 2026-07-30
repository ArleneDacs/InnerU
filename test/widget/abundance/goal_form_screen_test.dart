import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
