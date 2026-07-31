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

  // ---------------------------------------------------------------------
  // Round 2 Important: every write handler on this screen ran its mutating
  // call bare -- no try/catch anywhere -- and the only snackbars were
  // unconditional SUCCESS messages shown after the await. So a rejected
  // write (a coach's 401 now that coaches can READ a mentee's quest, an
  // offline device, a 500) did nothing visible at all. Delete was the worst
  // case: after a "this cannot be undone" confirmation, a failed delete
  // showed nothing whatsoever.
  // ---------------------------------------------------------------------

  testWidgets('a failed delete keeps the screen open and says why',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RejectingGoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: id, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    // Confirm in the "this cannot be undone" dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not delete quest'), findsOneWidget);
    // The delete failed, so the screen must still be here -- popping would
    // tell the member their quest is gone when it is not.
    expect(find.byType(GoalDetailScreen), findsOneWidget);
    expect(await _goalExists(firestore, id), isTrue);
  });

  testWidgets('a failed progress save says why instead of claiming success',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RejectingGoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: id, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '100');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not save progress'), findsOneWidget);
    expect(find.text('Progress saved'), findsNothing);
  });

  testWidgets('a failed status change says why', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RejectingGoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: id, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(DropdownButton<GoalStatus>));
    await tester.tap(find.byType(DropdownButton<GoalStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completed').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not update the quest status'),
        findsOneWidget);
  });

  testWidgets('a failed action-plan add says why rather than doing nothing',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = _RejectingGoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'A12'});
    final id = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.professional,
      title: 'Launch',
      targetDate: DateTime(2026, 9, 1),
      goalType: GoalType.milestone,
      planTitles: ['Design'],
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: id, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Add an action plan...'),
      'Print the banners',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add'));
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not add the action plan'), findsOneWidget);
  });
}

Future<bool> _goalExists(FakeFirebaseFirestore firestore, String id) async =>
    (await firestore.collection('goals').doc(id).get()).exists;

/// A [GoalsService] whose every write fails, the way the real API fails a
/// coach's write on a mentee's quest (401), a device with no network, or a
/// server error. Reads still work off the fake Firestore, so the screen
/// renders normally and only the write paths are under test.
class _RejectingGoalsService extends GoalsService {
  _RejectingGoalsService(super.legacyFirestore);

  static Never _reject() => throw Exception('Unauthorized.');

  @override
  Future<void> deleteGoal(String goalId) async => _reject();

  @override
  Future<void> setGoalMeasure({
    required String goalId,
    required String actorId,
    required double currentValue,
  }) async =>
      _reject();

  @override
  Future<void> updateGoal({
    required String goalId,
    required String actorId,
    String? title,
    String? description,
    String? notes,
    GoalStatus? status,
    DateTime? startDate,
    DateTime? targetDate,
    GoalDirection? direction,
    double? targetValue,
    double? currentValue,
    String? unit,
    GoalType? goalType,
    TargetPeriod? targetPeriod,
  }) async =>
      _reject();

  @override
  Future<String> addActionPlan({
    required String goalId,
    required String title,
    required String actorId,
  }) async =>
      _reject();

  @override
  Future<void> logMeritTarget({
    required String goalId,
    required String actorId,
  }) async =>
      _reject();

  @override
  Future<void> goExtraMile({
    required String goalId,
    required String actorId,
    required double amount,
  }) async =>
      _reject();
}
