import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedometer/pedometer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:selfcare_projects/src/features/authentication/screen/step_tracker.dart/steptracker_screen.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';
import 'package:selfcare_projects/src/utils/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      '"Enable Step Tracking" button is hidden once permission is already granted, without needing an unrelated rebuild',
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
    addTearDown(AppSessionService.instance.clear);
    addTearDown(() => CompanyThemeService.clearCachedThemeForUser('42'));

    // No background/pedometer events are ever emitted, so nothing else
    // triggers a rebuild after the initial permission check.
    final backgroundController = StreamController<int>.broadcast();
    final pedometerController = StreamController<StepCount>.broadcast();
    addTearDown(backgroundController.close);
    addTearDown(pedometerController.close);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StepTracker(
          debugBackgroundStepStream: backgroundController.stream,
          debugStepCountStream: pedometerController.stream,
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

    expect(find.text('Enable Step Tracking'), findsNothing);
  });
}
