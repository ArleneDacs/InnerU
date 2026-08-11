import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/features/authentication/screen/sleep_tracker/sleep_tracker.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

Future<void> _pumpSleepTracker(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: const SleepTracker(),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'inneru.app.session': '',
    });
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final session = AppSession(
      id: 77,
      token: 'sleep-test-token',
      name: 'Sleepy Tester',
      email: 'sleepy@example.com',
      role: 'user',
      isCoach: false,
    );
    await AppSessionService.instance.setSession(session);
    CompanyThemeService.cacheThemeForUser('77', CompanyThemeData.standard);
  });

  tearDown(() async {
    await AppSessionService.instance.clear();
    CompanyThemeService.clearCachedThemeForUser('77');
  });

  testWidgets(
      'default sleep goal shows 8h 0m and "Change" opens a duration picker',
      (tester) async {
    await _pumpSleepTracker(tester);

    expect(find.text('8h 0m'), findsWidgets);

    await tester.tap(find.text('Change').last);
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTimerPicker), findsOneWidget);
  });

  testWidgets(
      'a saved goal with a minutes component loads and displays correctly',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sleep_tracker_goal_hours_77', 7);
    await prefs.setInt('sleep_tracker_goal_minutes_77', 30);

    await _pumpSleepTracker(tester);

    expect(find.text('7h 30m'), findsWidgets);
  });

  testWidgets(
      'a legacy goal saved with only the hours key (no minutes key) still loads correctly',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sleep_tracker_goal_hours_77', 6);

    await _pumpSleepTracker(tester);

    expect(find.text('6h 0m'), findsWidgets);
  });
}
