import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

Future<void> _pumpStepTracker(
  WidgetTester tester, {
  required Stream<int> backgroundSteps,
  required Stream<StepCount> pedometerSteps,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: StepTracker(
        debugBackgroundStepStream: backgroundSteps,
        debugStepCountStream: pedometerSteps,
        debugRemoteTodayStepsLoader: (userId, date) async => 0,
        debugUserDataLoader: () async => <String, dynamic>{
          'daily_step_goal': 5000,
          'dailyStepGoal': 5000,
          'username': 'Test Walker',
          'name': 'Test Walker',
        },
        debugAutoGrantStepPermission: true,
        debugSkipBackgroundService: true,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StepTracker resume and background updates', () {
    testWidgets('shows background updates and reloads cached steps on resume',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'inneru.app.session': '',
      });

      final session = AppSession(
        id: 42,
        token: 'test-token',
        name: 'Test Walker',
        email: 'walker@example.com',
        role: 'user',
        isCoach: false,
      );
      await AppSessionService.instance.setSession(session);
      CompanyThemeService.cacheThemeForUser('42', CompanyThemeData.standard);

      final backgroundController = StreamController<int>.broadcast();
      final pedometerController = StreamController<StepCount>.broadcast();
      addTearDown(backgroundController.close);
      addTearDown(pedometerController.close);
      addTearDown(AppSessionService.instance.clear);
      addTearDown(() => CompanyThemeService.clearCachedThemeForUser('42'));

      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt('saved_steps_42', 800);
      await prefs.setInt('initial_steps_42', -1);
      await prefs.setInt('step_offset_42', 0);
      await prefs.setString('last_saved_date_42', today);
      await prefs.setInt('daily_step_goal_42', 5000);
      await prefs.setString('step_cache_owner_uid', '42');

      await _pumpStepTracker(
        tester,
        backgroundSteps: backgroundController.stream,
        pedometerSteps: pedometerController.stream,
      );

      expect(find.text('800'), findsWidgets);

      backgroundController.add(1200);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1200'), findsWidgets);

      prefs = await SharedPreferences.getInstance();
      await prefs.setInt('saved_steps_42', 1500);
      await prefs.setInt('step_offset_42', 0);
      await prefs.setInt('initial_steps_42', -1);

      final state = tester.state<StepTrackerState>(
        find.byType(StepTracker),
      );
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('1500'), findsWidgets);
    });
  });
}
