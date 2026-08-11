import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/meditation/meditation_streak_rewards_screen.dart';
import 'package:selfcare_projects/src/services/meditation_streak_service.dart';

void main() {
  testWidgets('keeps Steps reward card content available on a compact iPhone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: MeditationStreakRewardsScreen(
          activityType: ActivityStreakType.steps,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Steps Rewards'), findsOneWidget);
    expect(find.text('First Stride'), findsOneWidget);
    expect(find.text('Keep a 3-day streak'), findsOneWidget);
    // PageView keeps a neighboring reward page alive for a smooth swipe.
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
