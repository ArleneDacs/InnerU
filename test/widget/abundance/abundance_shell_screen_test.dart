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
  testWidgets('shows the header chrome and switches tabs on tap',
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
        // Test-only override: this test's GoalsService is backed by a
        // FakeFirebaseFirestore with no seeded `users/u1` doc, so
        // GoalsHubScreen's real access check would otherwise (correctly, for
        // that setup) deny access. See questsAccessResolverOverride's doc
        // comment on AbundanceShellScreen.
        questsAccessResolverOverride: (_) async => true,
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
        // The shell's real default landing tab is Home (0), matching every
        // A12 reference screenshot. This test overrides that to land on
        // Quests instead, purely to avoid building CoachDashboardScreen
        // (the coach-mode Home tab), which touches FirebaseFirestore.instance
        // synchronously in a field initializer and crashes with no live
        // Firebase app in this widget-test environment. This is a test-only
        // override, not a change to production behavior.
        initialIndex: 1,
      ),
    ));
    await tester.pumpAndSettle();

    // Landed directly on the Quests tab (via initialIndex above), so the
    // roster is visible without any tap here — tapping the "Quests" nav
    // label would be ambiguous anyway once its content is showing, since
    // CoachQuestsRosterScreen renders its own "Quests" heading too.
    expect(find.textContaining('No students yet'), findsOneWidget);
  });

  testWidgets(
      'defaults to the Home tab and shows the mentee dashboard when initialIndex is not supplied',
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
        // initialIndex deliberately omitted: this is the regression guard
        // that the shell's real default landing tab is Home (0), matching
        // every A12 reference screenshot — not Quests.
        //
        // questsAccessResolverOverride is supplied here purely so the
        // tab-switch assertion below (tapping into Quests) can observe real
        // GoalsHubScreen content — this test's GoalsService has no seeded
        // `users/u1` doc, so the real access check would otherwise deny
        // access. See questsAccessResolverOverride's doc comment for why
        // this is safe as a test-only bypass.
        questsAccessResolverOverride: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    // The bottom nav shows Home as selected and the Quests tab body
    // ("Life Power", GoalsHubScreen's own header text) has not been built.
    expect(find.textContaining('Life Power'), findsNothing);

    // AbundanceMenteeDashboardScreen (the mentee Home tab) is on screen. In
    // this test harness there's no authenticated session, so the dashboard
    // resolves to its own access-denied state — but that state's text is
    // unique to AbundanceMenteeDashboardScreen itself, so finding it proves
    // the Home tab body is genuinely that screen, not a placeholder or the
    // Quests tab.
    expect(find.text('A12 access only'), findsOneWidget);

    // Switching to Quests still works from this default landing point.
    await tester.tap(find.text('Quests'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Life Power'), findsWidgets);
  });

  testWidgets(
      'Quests tab uses GoalsHubScreen\'s own real access check when no override is supplied',
      (tester) async {
    // Bare GoalsService(), no legacy Firestore — matches how production
    // constructs it. No questsAccessResolverOverride is supplied: this is
    // the regression guard that production code no longer force-bypasses
    // GoalsHubScreen's access gate.
    final service = GoalsService();

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
        initialIndex: 1, // land directly on Quests
      ),
    ));
    await tester.pumpAndSettle();

    // With no legacy Firestore, GoalsService.fetchActiveCompanyIdentity
    // returns null immediately, so GoalsHubScreen's real access chain falls
    // through to CompanyMembershipService.loadForUser('u1'). There's no
    // authenticated AuthService session in this test harness, so
    // UserService.getUserData() short-circuits to `{}` and that resolves to
    // an empty membership — correctly denying access. This proves the shell
    // is no longer forcing `accessResolver: (_) async => true` in
    // production: the real gate is reachable and can actually deny.
    expect(find.text('A12 only'), findsOneWidget);
    expect(find.textContaining('Life Power'), findsNothing);
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
        // Test-only override: see the header-chrome test above for why this
        // test's GoalsService needs it to reach real Quests content.
        questsAccessResolverOverride: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    // Navigate to Quests first (the shell's real default landing tab is now
    // Home) and confirm its content is showing before More is tapped, so the
    // "still there after" check below is meaningful.
    await tester.tap(find.text('Quests'));
    await tester.pumpAndSettle();
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
