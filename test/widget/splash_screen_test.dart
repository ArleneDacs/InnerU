import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/splash_screen.dart';
import 'package:selfcare_projects/src/services/app_update_service.dart';

void main() {
  group('SplashScreen force-update gating', () {
    testWidgets(
        'shows the blocking dialog when the update check reports outdated',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          checkForUpdate: () async =>
              AppUpdateCheckResult.outdated('https://apps.apple.com/app/id1'),
          onUpdateNow: (_) async {},
        ),
      ));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('A new version is available'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('navigates to login when the app is up to date',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          checkForUpdate: () async => AppUpdateCheckResult.upToDate,
        ),
      ));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('A new version is available'), findsNothing);
    });

    testWidgets('navigates to login when the update check fails',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          checkForUpdate: () =>
              Future<AppUpdateCheckResult>.error('network down'),
        ),
      ));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('A new version is available'), findsNothing);
    });

    testWidgets('waits for a slow check before navigating', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          checkForUpdate: () => Future.delayed(
            const Duration(seconds: 4),
            () => AppUpdateCheckResult.outdated('https://apps.apple.com/app/id1'),
          ),
          onUpdateNow: (_) async {},
        ),
      ));

      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(LoginScreen), findsNothing); // 3s branding delay elapsed, but check isn't done yet — must not have navigated

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('A new version is available'), findsOneWidget); // now the slow check has resolved and blocked correctly
    });
  });
}
