import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

const _declaration = 'I see myself finishing what I start';

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

  testWidgets('completing all 4 steps and submitting creates the quest',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());
    await FakeFirebaseFirestore().collection('users').doc('u1').set({
      'companyId': 'c1',
    });

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

    await tester.tap(find.text('Personal'));
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '10');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 — When & qualities'), findsOneWidget);
    await tester.tap(find.text('Commitment'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 4 — Declaration'), findsOneWidget);
    expect(find.textContaining('I see myself finishing what I start'), findsWidgets);
    expect(find.text('Commitment'), findsWidgets);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    // Submitting pops the wizard back to its caller.
    expect(find.byType(GoalFormScreen), findsNothing);
  });

  testWidgets(
      'submitting the wizard persists a non-blank title/description derived '
      'from the declaration -- the gap this task must close is a quest '
      'silently saved with a blank title/description',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({
      'activeCompanyId': 'A12',
      'companyId': 'A12',
    });

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      _declaration,
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal'));
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '10');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Commitment'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    final docs = await firestore.collection('goals').get();
    expect(docs.docs, hasLength(1));
    final data = docs.docs.single.data();

    // This is the assertion that actually closes the gap: if `_title`/
    // `_description` were left wired to nothing (as they were before this
    // task), these would be empty strings and the test below would fail --
    // merely reaching and tapping Submit is not enough proof.
    expect(data['title'], isNotEmpty);
    expect(data['title'], contains(_declaration));
    expect(data['description'], isNotEmpty);
    expect(data['description'], contains(_declaration));
    expect(data['description'], contains('Commitment'));
  });

  testWidgets(
      'chip taps never clobber qualities the member typed directly into the '
      'free-text field',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      _declaration,
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal'));
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '10');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 — When & qualities'), findsOneWidget);

    // Tap a chip first -- syncs the free-text field to "Commitment".
    await tester.tap(find.text('Commitment'));
    await tester.pumpAndSettle();

    // Now type directly into the free-text field, by hand, adding a quality
    // no chip offers.
    await tester.enterText(
      find.byKey(const Key('quest-qualities-field')),
      'Commitment, Vision',
    );
    await tester.pumpAndSettle();

    // Tap a second chip.
    await tester.tap(find.text('Discipline'));
    await tester.pumpAndSettle();

    final qualitiesField = tester.widget<TextField>(
      find.byKey(const Key('quest-qualities-field')),
    );
    // The manually-typed "Vision" must survive the subsequent chip tap. If
    // `_toggleQuality` recomputed off a stale Set instead of re-parsing the
    // live text, "Vision" would have been silently discarded here.
    expect(qualitiesField.controller!.text, 'Commitment, Vision, Discipline');
  });

  testWidgets(
      'a punctuation-only declaration that clears the 3-character gate '
      'still persists a non-blank composed description',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({
      'activeCompanyId': 'A12',
      'companyId': 'A12',
    });

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    // "..." is 3 characters -- the step-0 gate only counts characters, so
    // this clears it and the wizard advances, even though the declaration is
    // purely punctuation.
    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      '...',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 — How'), findsOneWidget);

    await tester.tap(find.text('Personal'));
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '10');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 4 of 4 — Declaration'), findsOneWidget);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    final docs = await firestore.collection('goals').get();
    expect(docs.docs, hasLength(1));
    final data = docs.docs.single.data();

    // With the buggy `+`-quantified regex (`[.!?]+\s*$`), stripping ALL
    // trailing punctuation from "..." leaves an empty `goal`, so
    // `_composeDeclaration` returns '' and `description` is persisted blank.
    // The corrected regex (`[.!?]\s*$`, exactly one character) strips only
    // the last dot, leaving ".." -- non-empty -- so a real composed sentence
    // is persisted instead.
    expect(data['description'], isNotEmpty);
    expect(data['description'], contains('on or before'));
  });
}
