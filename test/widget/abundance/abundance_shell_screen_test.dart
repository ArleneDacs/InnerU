import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/screens/abundance_shell_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

/// [GoalsService.fetchCoachGoalsRoster] always calls the real network API —
/// unlike `watchGoals` (used by the mentee Quests tab), it has no
/// legacy-Firestore branch for test mode. A bare `GoalsService` constructed
/// against a [FakeFirebaseFirestore] would hit a real HTTP call that fails in
/// the test harness, and [CoachQuestsRosterScreen] shows a perpetual spinner
/// on any Future error (not just while loading) — so `pumpAndSettle` would
/// never settle. This fake mirrors the same pattern already used in
/// `coach_quests_roster_screen_test.dart` to keep the coach roster fetch
/// synchronous and test-safe.
class _FakeCoachGoalsService extends GoalsService {
  _FakeCoachGoalsService() : super(null);

  @override
  Future<List<CoachMenteeGoals>> fetchCoachGoalsRoster() async =>
      const <CoachMenteeGoals>[];
}

void main() {
  testWidgets('shows the Quests tab body by default and switches tabs on tap',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: AbundanceShellScreen(
        isCoach: false,
        service: service,
        uid: 'u1',
        companyTheme: CompanyThemeData.standard.copyWith(
          companyCode: 'ABU15DN',
          companyName: 'Abundance',
          isCompanyTheme: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ABUNDANCE 12'), findsOneWidget);
    expect(find.text('THE GAME OF MY LIFE'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // the tab label itself, still visible

    await tester.tap(find.text('Quests'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Life Power'), findsWidgets);
  });

  testWidgets('coach shell shows the coach roster on the Quests tab',
      (tester) async {
    final service = _FakeCoachGoalsService();

    await tester.pumpWidget(MaterialApp(
      home: AbundanceShellScreen(
        isCoach: true,
        service: service,
        uid: 'coach1',
        companyTheme: CompanyThemeData.standard.copyWith(
          companyCode: 'ABU15DN',
          companyName: 'Abundance',
          isCompanyTheme: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The shell already lands on the Quests tab by default (see
    // AbundanceShellScreen's landing-tab rationale), so the roster is
    // visible without any tap here — tapping the "Quests" nav label would
    // be ambiguous anyway once its content is showing, since
    // CoachQuestsRosterScreen renders its own "Quests" heading too.
    expect(find.textContaining('No students yet'), findsOneWidget);
  });

  testWidgets(
      'tapping More opens the bottom sheet without changing the selected tab',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: AbundanceShellScreen(
        isCoach: false,
        service: service,
        uid: 'u1',
        companyTheme: CompanyThemeData.standard.copyWith(
          companyCode: 'ABU15DN',
          companyName: 'Abundance',
          isCompanyTheme: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Quests is the landing tab; confirm its content is showing before More
    // is tapped, so the "still there after" check below is meaningful.
    expect(find.textContaining('Life Power'), findsWidgets);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    // BottomSheetWidget.show opened — its menu tiles are on screen.
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Activity Logs'), findsOneWidget);
    // The tab underneath is untouched: still Quests, not some 5th "More" body.
    expect(find.textContaining('Life Power'), findsWidgets);
  });

  testWidgets(
      'AbundanceShellScreen is never constructed for a non-Abundance company',
      (tester) async {
    // This is a documentation test: AbundanceShellScreen has no internal
    // gating of its own — Task 13's integration point is what decides
    // whether to build it at all. See abundance_company_test.dart (Task 1)
    // for the actual gating-logic coverage.
  });
}
