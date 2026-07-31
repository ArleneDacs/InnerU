import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_assets.dart';
import 'package:selfcare_projects/src/features/abundance/domain/domain.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goals_hub_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  testWidgets('hub lists the goal and flags missing categories',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({
      'companyId': 'A12',
      'companyCode': 'A12',
      'companyName': 'Abundance 12',
      'activeCompanyId': 'A12',
      'activeCompanyCode': 'A12',
      'activeCompanyName': 'Abundance 12',
    });
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
      home: GoalsHubScreen(
        service: service,
        uid: 'u1',
        accessResolver: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Run 100 km'), findsOneWidget);
    // Matches A12's own subtitle verbatim (goals/page.tsx:118-121), which
    // stops at "Life Power." The sentence that used to follow pointed at a
    // "Todo List" destination this shell does not have and claimed a start
    // date the wizard never collects.
    expect(
      find.textContaining('combined into your Life Power.'),
      findsOneWidget,
    );
    expect(find.textContaining('Todo List'), findsNothing);
    // Personal is held; the other two required categories are named as gaps.
    expect(find.textContaining('Professional'), findsWidgets);
    expect(find.textContaining('Contribution'), findsWidgets);
  });

  testWidgets('quest title is not forced to uppercase', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'c1'});
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
      home: GoalsHubScreen(
        service: service,
        uid: 'u1',
        accessResolver: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Run 100 km'), findsOneWidget);
    expect(find.text('RUN 100 KM'), findsNothing);
  });

  testWidgets('access resolution does not depend on the loadForUser singleton',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({
      'companyId': 'c1',
      'activeCompanyCode': 'ABU15DN',
      'activeCompanyName': 'Abundance',
    });

    // No accessResolver override here — this must resolve access from the
    // GoalsService/user data passed in, not from a CompanyMembershipService
    // singleton that isn't configured in this test.
    await tester.pumpWidget(MaterialApp(
      home: GoalsHubScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Quests'), findsWidgets);
    // The assertion above is satisfiable by a false positive: the
    // access-DENIED gate panel's copy also contains the word "Quests", so
    // this guard additionally proves access was actually GRANTED (the gate
    // did not render) rather than merely that some text says "Quests"
    // somewhere on screen.
    expect(find.text('A12 only'), findsNothing);
  });
  // -------------------------------------------------------------------
  // Whole-branch review, Important 5: abundanceQuestSceneAsset and
  // abundanceBackdropAsset (Task 4) shipped four WebP plates into the app
  // bundle with zero production call sites — they were referenced only from
  // their own unit test. These assert the art is genuinely on screen.
  // -------------------------------------------------------------------
  testWidgets('quest cards render their category scene art and the page '
      'carries the backdrop plate', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 12, 31),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalsHubScreen(
        service: service,
        uid: 'u1',
        accessResolver: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    final assetNames = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<AssetImage>()
        .map((provider) => provider.assetName)
        .toSet();

    expect(assetNames, contains(abundanceBackdropAsset));
    expect(assetNames, contains(abundanceQuestSceneAsset('PERSONAL')));
  });

  // ---------------------------------------------------------------------
  // Round 2: the header's off-source "Todo List" claim was fixed, but the
  // identical claim survived in the EMPTY STATE -- which the header's own
  // regression test could never catch, because it seeds a goal and so the
  // empty state never renders. These seed NO goals on purpose.
  // ---------------------------------------------------------------------

  testWidgets(
      'the empty state names no destination this shell does not have and no '
      'field the wizard does not collect', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    // Deliberately no goals: this is the branch the header test can't reach.

    await tester.pumpWidget(MaterialApp(
      home: GoalsHubScreen(
        service: service,
        uid: 'u1',
        accessResolver: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    // Proves the empty state is really what's on screen.
    expect(find.text('No quests yet'), findsOneWidget);

    // There is no "Todo List" anywhere in this experience, and the wizard
    // collects one deadline -- never a start date and an end date.
    expect(find.textContaining('Todo List'), findsNothing);
    expect(find.textContaining('start and end dates'), findsNothing);
    // The way to create a quest is the button right here.
    expect(find.widgetWithText(FilledButton, 'New quest'), findsWidgets);
  });

  testWidgets(
      'the category-filtered empty state carries A12\'s own reason for why '
      'the gap matters', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 12, 31),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalsHubScreen(
        service: service,
        uid: 'u1',
        accessResolver: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    // Filter to a category the member holds no quest in. The filter chip's
    // label is "<category>  <count>" -- matched exactly so this cannot
    // accidentally tap the category's tile in the summary grid instead.
    await tester.ensureVisible(find.text('Professional  0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Professional  0'));
    await tester.pumpAndSettle();

    expect(find.text('No quests in this category yet'), findsOneWidget);
    // Verbatim from A12's own empty state (goals/page.tsx:263).
    expect(
      find.textContaining('an empty one scores 0'),
      findsOneWidget,
    );
    expect(find.textContaining('Todo List'), findsNothing);
  });
}
