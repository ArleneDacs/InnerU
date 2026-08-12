import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/app_session_service.dart';
import 'package:selfcare_projects/src/services/default_landing_screen.dart';

void main() {
  group('DefaultLandingScreen', () {
    test('uses Dashboard for missing or unknown persisted values', () {
      expect(
        DefaultLandingScreen.fromStorageValue(null),
        DefaultLandingScreen.dashboard,
      );
      expect(
        DefaultLandingScreen.fromStorageValue('not-a-screen'),
        DefaultLandingScreen.dashboard,
      );
    });

    test('maps semantic destinations to the standard setup shell', () {
      expect(DefaultLandingScreen.meditation.standardSetupIndex, 0);
      expect(DefaultLandingScreen.steps.standardSetupIndex, 1);
      expect(DefaultLandingScreen.dashboard.standardSetupIndex, 2);
      expect(DefaultLandingScreen.goals.standardSetupIndex, 3);
      expect(DefaultLandingScreen.community.standardSetupIndex, 4);
      expect(DefaultLandingScreen.profile.standardSetupIndex, 5);
      expect(
        DefaultLandingScreen.fromStandardSetupIndex(3),
        DefaultLandingScreen.goals,
      );
    });

    test('only maps supported Abundance destinations and falls back to Home',
        () {
      expect(
        DefaultLandingScreen.availableFor(isAbundance: true),
        orderedEquals([
          DefaultLandingScreen.dashboard,
          DefaultLandingScreen.goals,
          DefaultLandingScreen.profile,
        ]),
      );
      expect(DefaultLandingScreen.dashboard.safeAbundanceShellIndex, 0);
      expect(DefaultLandingScreen.goals.safeAbundanceShellIndex, 1);
      expect(DefaultLandingScreen.profile.safeAbundanceShellIndex, 3);
      expect(DefaultLandingScreen.community.safeAbundanceShellIndex, 0);
    });

    test('round-trips through the persisted authenticated session', () {
      const session = AppSession(
        id: 42,
        token: 'secure-token',
        name: 'InnerU Member',
        email: 'member@example.com',
        role: 'user',
        isCoach: false,
        defaultLandingScreen: 'community',
      );

      final restored = AppSession.fromJson(session.toJson());

      expect(restored.defaultLandingScreen, 'community');
    });
  });
}
