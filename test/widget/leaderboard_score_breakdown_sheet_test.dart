import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/leaderboard_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('leaderboard score sheet shows only goal and daily tracker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: LeaderboardScoreBreakdownSheet(
              name: 'Arlene',
              teamName: 'GENOKUS',
              goalScore: 82,
              dailyTrackerScore: 64,
              totalScore: 73,
              accentColor: Colors.teal,
              theme: CompanyThemeData.standard,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Arlene score'), findsOneWidget);
    expect(find.text('Goal score'), findsOneWidget);
    expect(find.text('Daily tracker'), findsOneWidget);
    expect(find.text('Total score'), findsOneWidget);
    expect(find.text('A12'), findsNothing);
    expect(find.text('Consistency'), findsNothing);
    expect(find.text('Streak'), findsNothing);
    expect(find.text('check-ins'), findsNothing);
  });

  testWidgets('group member sheet uses daily tracker and goals only', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const session = AppSession(
      id: 42,
      token: 'leaderboard-test-token',
      name: 'Coach Test',
      email: 'coach@example.com',
      role: 'coach',
      isCoach: true,
    );
    await AppSessionService.instance.setSession(session);
    CompanyThemeService.cacheThemeForUser('42', CompanyThemeData.standard);
    addTearDown(AppSessionService.instance.clear);
    addTearDown(() => CompanyThemeService.clearCachedThemeForUser('42'));

    const member = LeaderboardApiGroupMember(
      userId: '7',
      name: 'Jenny',
      score: 73,
      goalScore: 82,
      coreTaskScore: 64,
      overallScore: 73,
      rank: 1,
      teamName: '2B-ASCEND',
    );
    const snapshot = LeaderboardApiSnapshot(
      companyCode: 'ASCEND',
      companyName: 'Ascend Company',
      leaderboardPeriodStart: null,
      leaderboardPeriodEnd: null,
      entries: <LeaderboardApiCompanyEntry>[],
      groups: <LeaderboardApiGroup>[
        LeaderboardApiGroup(
          groupId: 'group-1',
          groupName: 'Ascend Team',
          coachName: 'Coach Test',
          companyName: 'Ascend Company',
          totalScore: 73,
          entries: <LeaderboardApiGroupMember>[member],
          photoUrl: null,
        ),
      ],
      menteeEntries: <LeaderboardApiGroupMember>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Leaderboard(debugLoader: () async => snapshot),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ascend Team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#1 Jenny'));
    await tester.pumpAndSettle();

    expect(find.text('Jenny score'), findsOneWidget);
    expect(find.text('Combined goal and daily tracker score.'), findsOneWidget);
    expect(find.text('Team: 2B-ASCEND'), findsOneWidget);
    expect(find.text('Goal score'), findsOneWidget);
    expect(find.text('Daily tracker'), findsOneWidget);
    expect(find.text('Total score'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('82 pts'), findsOneWidget);
    expect(find.text('64'), findsOneWidget);
    expect(find.text('64 pts'), findsOneWidget);
    expect(find.text('73'), findsOneWidget);

    expect(find.text("Jenny's Points"), findsNothing);
    expect(find.text('Call'), findsNothing);
    expect(find.text('Steps'), findsNothing);
    expect(find.text('Exercise'), findsNothing);
    expect(find.text('Meditation'), findsNothing);
    expect(find.text('Add Value'), findsNothing);
    expect(find.text('Learning'), findsNothing);
    expect(find.text('Goals'), findsNothing);
    expect(find.text('Total Points'), findsNothing);
  });

  testWidgets('tapping score card scrolls to the current user rank', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const session = AppSession(
      id: 42,
      token: 'leaderboard-rank-test-token',
      name: 'Arlene',
      email: 'arlene@example.com',
      role: 'member',
      isCoach: false,
    );
    await AppSessionService.instance.setSession(session);
    CompanyThemeService.cacheThemeForUser('42', CompanyThemeData.standard);
    addTearDown(AppSessionService.instance.clear);
    addTearDown(() => CompanyThemeService.clearCachedThemeForUser('42'));

    final companyEntries = List<LeaderboardApiCompanyEntry>.generate(12, (
      index,
    ) {
      final placement = index + 1;
      final isCurrentUser = placement == 10;
      final score = 100 - placement;
      return LeaderboardApiCompanyEntry(
        userId: isCurrentUser ? '42' : 'user-$placement',
        name: isCurrentUser ? 'Arlene' : 'Member $placement',
        score: score,
        goalScore: score,
        coreTaskScore: score,
        overallScore: score,
        rank: placement,
      );
    });
    final snapshot = LeaderboardApiSnapshot(
      companyCode: 'STANDARD',
      companyName: 'Standard Company',
      leaderboardPeriodStart: null,
      leaderboardPeriodEnd: null,
      entries: companyEntries,
      groups: const <LeaderboardApiGroup>[],
      menteeEntries: const <LeaderboardApiGroupMember>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Leaderboard(debugLoader: () async => snapshot),
      ),
    );
    await tester.pumpAndSettle();

    const currentUserRowKey = ValueKey<String>('leaderboard-entry-42');
    expect(find.byKey(currentUserRowKey), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('current-user-score-card')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(currentUserRowKey).hitTestable(), findsOneWidget);
    expect(find.text('#10').hitTestable(), findsOneWidget);
    expect(find.text('You').hitTestable(), findsOneWidget);
  });
}
