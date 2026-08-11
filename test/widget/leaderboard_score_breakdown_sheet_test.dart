import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/leaderboard_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'leaderboard score sheet shows only daily tracker, not goal score', (
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
    expect(find.text('Goal score'), findsNothing);
    expect(find.text('Daily tracker'), findsOneWidget);
    expect(find.text('Overall score (tie-breaker)'), findsOneWidget);
    expect(find.text('A12'), findsNothing);
    expect(find.text('Consistency'), findsNothing);
    expect(find.text('Streak'), findsNothing);
    expect(find.text('check-ins'), findsNothing);
  });

  testWidgets('group member sheet uses daily tracker and goals only', (
    tester,
  ) async {
    const member = LeaderboardEntry(
      userId: '7',
      name: 'Jenny',
      score: 73,
      goalScore: 82,
      coreTaskScore: 64,
      rank: 1,
      activity: UserActivity(),
      teamName: '2B-ASCEND',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: GroupLeaderboardScoreBreakdownSheet(
              entry: member,
              theme: CompanyThemeData.standard,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Jenny score'), findsOneWidget);
    expect(
      find.text(
        'Leaderboard rank is based on when today\'s Daily Tracker is '
        'completed. Score breaks an exact completion-time tie.',
      ),
      findsOneWidget,
    );
    expect(find.text('Team: 2B-ASCEND'), findsOneWidget);
    expect(find.text('Goal score'), findsNothing);
    expect(find.text('Daily tracker'), findsOneWidget);
    expect(find.text('Overall score (tie-breaker)'), findsOneWidget);
    expect(find.text('82'), findsNothing);
    expect(find.text('82 pts'), findsNothing);
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

  testWidgets(
    'company leaderboard places an earlier finisher above a later higher score',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
      const session = AppSession(
        id: 77,
        token: 'leaderboard-completion-order-token',
        name: 'Viewer',
        email: 'viewer@example.com',
        role: 'member',
        isCoach: false,
      );
      await AppSessionService.instance.setSession(session);
      CompanyThemeService.cacheThemeForUser('77', CompanyThemeData.standard);
      addTearDown(AppSessionService.instance.clear);
      addTearDown(() => CompanyThemeService.clearCachedThemeForUser('77'));

      const snapshot = LeaderboardApiSnapshot(
        companyCode: 'STANDARD',
        companyName: 'Standard Company',
        leaderboardPeriodStart: null,
        leaderboardPeriodEnd: null,
        entries: <LeaderboardApiCompanyEntry>[
          LeaderboardApiCompanyEntry(
            userId: 'later-high-score',
            name: 'A Later High Score',
            score: 98,
            goalScore: 98,
            coreTaskScore: 98,
            overallScore: 98,
            rank: 1,
            firstCompletedTrackerAt: '2026-08-11T10:00:00Z',
          ),
          LeaderboardApiCompanyEntry(
            userId: 'earlier-low-score',
            name: 'Z Earlier Low Score',
            score: 10,
            goalScore: 10,
            coreTaskScore: 10,
            overallScore: 10,
            rank: 2,
            firstCompletedTrackerAt: '2026-08-11T09:00:00Z',
          ),
          LeaderboardApiCompanyEntry(
            userId: 'latest',
            name: 'M Latest',
            score: 100,
            goalScore: 100,
            coreTaskScore: 100,
            overallScore: 100,
            rank: 3,
            firstCompletedTrackerAt: '2026-08-11T11:00:00Z',
          ),
        ],
        groups: <LeaderboardApiGroup>[],
        menteeEntries: <LeaderboardApiGroupMember>[],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Leaderboard(debugLoader: () async => snapshot),
        ),
      );
      await tester.pumpAndSettle();

      final earlierFinisherPodium = find
          .ancestor(
            of: find.text('Z Earlier Low Score'),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(
        find.descendant(
          of: earlierFinisherPodium,
          matching: find.text('Top 1'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping score card scrolls to the current user rank', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
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
