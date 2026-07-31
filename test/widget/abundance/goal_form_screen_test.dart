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
  // ---------------------------------------------------------------------
  // Critical 3 (whole-branch review): step 2 shipped with no measure/unit
  // field at all, so `_goalType` was hardcoded to MERIT for every new quest
  // and `unit` was always persisted blank. A12 derives MERIT vs MILESTONE
  // from the chosen measure (`isMilestoneMeasure(unit)`, goal-plan.ts:90),
  // it does not offer a separate type toggle.
  // ---------------------------------------------------------------------

  testWidgets(
      'choosing the MILESTONE measure creates a milestone quest with a '
      'non-empty unit persisted', (tester) async {
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
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quest-measure-field')),
      'MILESTONE',
    );
    await tester.pumpAndSettle();

    // A milestone quest is scored from its action plans, so it needs at
    // least one before step 2 will let go (goal-wizard.tsx:814).
    await tester.enterText(
      find.byKey(const Key('quest-plan-entry-field')),
      'Book the venue',
    );
    await tester.ensureVisible(find.text('+ Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4 — When & qualities'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    final docs = await firestore.collection('goals').get();
    expect(docs.docs, hasLength(1));
    final data = docs.docs.single.data();
    expect(data['goalType'], GoalType.milestone.code);
    expect(data['unit'], isNotEmpty);
    expect(data['unit'], 'MILESTONE');
  });

  testWidgets('a non-milestone measure is persisted as the quest unit',
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
    await tester.enterText(
      find.byKey(const Key('quest-measure-field')),
      'KM',
    );
    await tester.enterText(
      find.byKey(const Key('quest-target-value-field')),
      '100',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    final data = (await firestore.collection('goals').get()).docs.single.data();
    expect(data['goalType'], GoalType.merit.code);
    expect(data['unit'], 'KM');
  });

  testWidgets('step 2 rejects a target value of exactly 0', (tester) async {
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
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '0');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4 — How'), findsOneWidget);
    expect(
      find.textContaining('target value greater than 0'),
      findsOneWidget,
    );
  });

  testWidgets('step 2 rejects a negative target value', (tester) async {
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
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '-5');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4 — How'), findsOneWidget);
  });

  testWidgets('step 2 rejects a milestone quest with zero action plans',
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
    await tester.enterText(
      find.byKey(const Key('quest-measure-field')),
      'MILESTONE',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4 — How'), findsOneWidget);
    expect(
      find.textContaining('at least one action plan'),
      findsOneWidget,
    );
  });

  testWidgets(
      'editing an existing MILESTONE quest seeds the measure field so its '
      'type survives a round-trip through the wizard', (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());
    final existing = GoalSummary(
      id: 'g1',
      userId: 'u1',
      companyId: 'A12',
      title: 'Ship the launch',
      description: 'Ship the launch on or before June 1, 2026.',
      notes: null,
      status: GoalStatus.inProgress,
      progress: 0,
      category: GoalCategory.professional,
      goalType: GoalType.milestone,
      targetPeriod: TargetPeriod.none,
      direction: GoalDirection.gain,
      targetValue: 0,
      currentValue: 0,
      unit: '',
      startDate: DateTime(2026, 1, 1),
      targetDate: DateTime(2026, 6, 1),
      completedAt: null,
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1', existing: existing),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final measureField = tester.widget<TextField>(
      find.byKey(const Key('quest-measure-field')),
    );
    expect(measureField.controller!.text, 'MILESTONE');
  });

  // ---------------------------------------------------------------------
  // Round 2 Critical: restoring MILESTONE creation (091eb76) added a step-2
  // blocker requiring >= 1 action plan, but `_planTitles` was never seeded
  // from the quest's real, persisted plans on the EDIT path -- and
  // `updateGoal` has no `planTitles` parameter at all. So an existing
  // milestone quest could never be edited and saved again: the blocker was
  // unsatisfiable except by converting the quest away from milestone, or by
  // typing a plan that silently vanished on save.
  // ---------------------------------------------------------------------

  /// Creates a real milestone quest (with genuinely persisted action plans)
  /// in the fake backend and returns the `GoalSummary` the wizard would be
  /// handed by [GoalDetailScreen]'s Edit button.
  ///
  /// The summary is built by hand rather than read back through
  /// `service.watchGoal(id).first`: `watchGoal` is a Firestore snapshot
  /// stream whose first event never arrives inside `testWidgets`' FakeAsync
  /// zone without pumping, so awaiting it here hangs the test.
  Future<GoalSummary> seedMilestoneGoal(
    GoalsService service, {
    List<String> planTitles = const ['Book the venue'],
  }) async {
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.professional,
      title: 'Ship the launch',
      description: 'Ship the launch on or before June 1, 2026.',
      targetDate: DateTime(2026, 6, 1),
      goalType: GoalType.milestone,
      planTitles: planTitles,
    );
    return GoalSummary(
      id: id,
      userId: 'u1',
      companyId: 'A12',
      title: 'Ship the launch',
      description: 'Ship the launch on or before June 1, 2026.',
      notes: null,
      status: GoalStatus.inProgress,
      progress: 0,
      category: GoalCategory.professional,
      goalType: GoalType.milestone,
      targetPeriod: TargetPeriod.none,
      direction: GoalDirection.gain,
      targetValue: 0,
      currentValue: 0,
      unit: '',
      startDate: DateTime(2026, 1, 1),
      targetDate: DateTime(2026, 6, 1),
      completedAt: null,
    );
  }

  testWidgets(
      'an existing MILESTONE quest that already has an action plan can be '
      'edited and saved -- the wizard must not treat its persisted plans as '
      'absent', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final existing = await seedMilestoneGoal(service);

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1', existing: existing),
    ));
    await tester.pumpAndSettle();

    // Change something unrelated to the measure/plans.
    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      'I see myself shipping the launch on time',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 — How'), findsOneWidget);

    // The quest's one persisted plan is shown, and it satisfies the
    // milestone blocker without the member having to retype it.
    expect(find.text('Book the venue'), findsOneWidget);
    expect(find.textContaining('at least one action plan'), findsNothing);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4 — When & qualities'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 4 of 4 — Declaration'), findsOneWidget);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    // Saving pops the wizard back to its caller, and the edit landed.
    expect(find.byType(GoalFormScreen), findsNothing);
    final data = (await firestore.collection('goals').doc(existing.id).get())
        .data()!;
    expect(data['title'], 'I see myself shipping the launch on time');
    expect(data['goalType'], GoalType.milestone.code);
  });

  testWidgets(
      'a plan typed into the wizard while editing is really persisted, not '
      'silently dropped on save', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final existing = await seedMilestoneGoal(service);

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1', existing: existing),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('quest-plan-entry-field')),
      'Print the banners',
    );
    await tester.ensureVisible(find.text('+ Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    final plans = await firestore
        .collection('goals')
        .doc(existing.id)
        .collection('tasks')
        .get();
    final titles = plans.docs.map((d) => d.data()['title']).toList();
    // The pre-existing plan must survive (the wizard must not re-create or
    // replace it), and the newly typed one must actually exist afterwards.
    expect(titles, containsAll(<String>['Book the venue', 'Print the banners']));
    expect(titles.where((t) => t == 'Book the venue'), hasLength(1));
  });

  testWidgets(
      'editing a MILESTONE quest whose plans were all deleted is not a dead '
      'end -- adding one in the wizard unblocks it', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    // Reachable in production: every plan can be deleted from the quest
    // detail screen's Action Plans card after the quest was created.
    final existing = await seedMilestoneGoal(service, planTitles: const []);

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1', existing: existing),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Blocked, but with a stated reason and a usable way out on the screen.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 — How'), findsOneWidget);
    expect(find.textContaining('at least one action plan'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('quest-plan-entry-field')),
      'Rebuild the plan',
    );
    await tester.ensureVisible(find.text('+ Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4 — When & qualities'), findsOneWidget);
  });
}
