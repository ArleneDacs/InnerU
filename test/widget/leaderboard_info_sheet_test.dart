import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/services/leaderboard_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LeaderboardInfoSheet explains every scoring concept', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LeaderboardInfoSheet(theme: CompanyThemeData.standard),
          ),
        ),
      ),
    );

    expect(find.text('How scoring works'), findsOneWidget);
    expect(find.text('Daily Tracker score'), findsOneWidget);
    expect(find.text('Goals & To-Do completion'), findsNothing);
    expect(find.text('Leaderboard ranking'), findsOneWidget);
    expect(find.text('Medals & streaks'), findsOneWidget);

    // Each section carries a worked numeric example, not just prose.
    expect(find.text('EXAMPLE'), findsNWidgets(3));
    expect(
      find.text('Completed 4 of 6 activities\n4 ÷ 6 × 100 = 66.7% for that day'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Daily Tracker scores of 70%, 90%, and 50%\n'
        '(70 + 90 + 50) ÷ period days = leaderboard average',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Streak milestones (days): 3, 7, 14, 30, 60, 100\n'
        'A 14-day streak unlocks the 3, 7, and 14-day medals at once',
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('Got it'), 200);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
  });

  testWidgets('LeaderboardInfoSheet uses inclusive leaderboard period days', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: LeaderboardInfoSheet(
              theme: CompanyThemeData.standard,
              periodStart: DateTime(2026, 8, 1),
              periodEnd: DateTime(2026, 12, 31),
            ),
          ),
        ),
      ),
    );

    expect(
      find.text(
        'Daily Tracker scores of 70%, 90%, and 50%\n'
        '(70 + 90 + 50) ÷ 153 = 1.4% average',
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping the leaderboard help icon opens the info sheet', (
    tester,
  ) async {
    final snapshot = LeaderboardApiSnapshot(
      companyCode: 'STANDARD',
      companyName: 'Standard Company',
      leaderboardPeriodStart: null,
      leaderboardPeriodEnd: null,
      entries: const <LeaderboardApiCompanyEntry>[],
      groups: const <LeaderboardApiGroup>[],
      menteeEntries: const <LeaderboardApiGroupMember>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Leaderboard(debugLoader: () async => snapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('How scoring works'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('leaderboard-info-button')));
    await tester.pumpAndSettle();

    expect(find.text('How scoring works'), findsOneWidget);
    expect(find.text('Medals & streaks'), findsOneWidget);
  });
}
