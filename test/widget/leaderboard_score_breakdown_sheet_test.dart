import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

void main() {
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
}
