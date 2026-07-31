import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/abundance_mentee_dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/adminscreen/manage_companies.dart';

/// Regression coverage for the whole-branch review's Critical 1: several
/// company-gating heuristics survived Task 2's consolidation and still
/// required a literal `"12"` somewhere in the company name/code, so the real
/// Abundance company (code `ABU15DN`, name `ABUNDANCE`) failed every one of
/// them.
///
/// The `abundance_mentee_dashboard_screen.dart` case is the one that actually
/// broke the product: that screen is the Abundance shell's default Home tab,
/// so a real Abundance mentee opened the app straight onto an access-denied
/// panel. Its gate is exercised here through the top-level, test-visible
/// helper the screen now calls, because resolving a real dashboard load in a
/// widget test would require an authenticated session plus five network
/// singletons (`UserService`, `CompanyThemeService`, `DailyTrackerApiService`,
/// `EmotionService`, `CoachApiService`) that this codebase has no mocking
/// seam for — the same limitation already recorded for `GoalsService`'s
/// `_api`-backed methods in earlier task reports.
void main() {
  group('AbundanceMenteeDashboardScreen gate', () {
    test('grants access to the real Abundance company identity', () {
      expect(
        abundanceMenteeDashboardAccessAllowed(
          name: 'ABUNDANCE',
          code: 'ABU15DN',
        ),
        isTrue,
      );
    });

    test('grants access when only the code matches, case/space insensitive',
        () {
      expect(
        abundanceMenteeDashboardAccessAllowed(
          name: 'Some Other Name',
          code: '  abu15dn  ',
        ),
        isTrue,
      );
    });

    test('still denies access to unrelated companies', () {
      expect(
        abundanceMenteeDashboardAccessAllowed(name: 'Gencys', code: 'GEN01'),
        isFalse,
      );
      expect(
        abundanceMenteeDashboardAccessAllowed(name: '', code: ''),
        isFalse,
      );
    });
  });

  group('manage_companies isAbundanceCompany', () {
    test('matches the real Abundance company identity', () {
      expect(isAbundanceCompany('ABUNDANCE', 'ABU15DN'), isTrue);
    });

    test('does not match unrelated companies', () {
      expect(isAbundanceCompany('Gencys', 'GEN01'), isFalse);
    });
  });
}
