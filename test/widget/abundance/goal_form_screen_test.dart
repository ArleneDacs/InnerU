import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  testWidgets('form requires a title and creates a merit goal',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});

    // The form's fields (title through the recurring-target dropdown and
    // Save button) are taller than the default 800x600 test surface, which
    // would otherwise leave "Save goal" scrolled below the fold. Use a
    // taller — but same-width, so horizontal layout is unaffected — surface
    // so every field and the button are reachable without scrolling, as
    // they would be on a typical phone screen.
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    // Saving with no title trips the validator.
    await tester.tap(find.text('Save goal'));
    await tester.pumpAndSettle();
    expect(find.text('Title is required'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('goal-title')), 'Read 12 books');
    await tester.enterText(find.byKey(const Key('goal-target-value')), '12');
    await tester.tap(find.text('Save goal'));
    await tester.pumpAndSettle();

    final goals = await firestore.collection('goals').get();
    expect(goals.docs.length, 1);
    expect(goals.docs.first.data()['title'], 'Read 12 books');
    expect(goals.docs.first.data()['targetValue'], 12);
  });
}
