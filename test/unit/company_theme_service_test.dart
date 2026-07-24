import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

void main() {
  group('CompanyThemeService theme choices', () {
    const companyTheme = CompanyThemeData(
      companyName: 'Gencys',
      companyCode: 'GENCYS',
      primaryColor: Color(0xFF35CFC5),
      accentColor: Color(0xFF2E7DFF),
      backgroundColor: Color(0xFF07120F),
      surfaceColor: Color(0xFF10221D),
      inkColor: Colors.white,
      mutedInkColor: Color(0xFFB7ECEA),
      iconColor: Color(0xFF7FFFF8),
      logoUrl: 'https://example.com/logo.png',
      tagline: 'Company theme',
      isDark: true,
      isCompanyTheme: true,
    );

    test('company users can choose company theme', () {
      final choices = CompanyThemeService.availableThemeChoicesFor(
        companyTheme,
      );

      expect(choices.first.id, CompanyThemeService.companyThemeChoice);
      expect(choices.map((choice) => choice.id), contains('sage'));
      expect(choices.map((choice) => choice.id), contains('light'));
      expect(choices.map((choice) => choice.id), contains('dark'));
    });

    test('users without company do not see company theme option', () {
      final choices = CompanyThemeService.availableThemeChoicesFor(
        CompanyThemeData.standard,
      );

      expect(
        choices.map((choice) => choice.id),
        isNot(contains(CompanyThemeService.companyThemeChoice)),
      );
      expect(choices.map((choice) => choice.id), contains('sage'));
      expect(choices.map((choice) => choice.id), contains('light'));
      expect(choices.map((choice) => choice.id), contains('dark'));
    });

    test('suggested theme preserves company identity', () {
      final selectedTheme = CompanyThemeService.applyThemeChoice(
        companyTheme,
        CompanyThemeService.tealThemeChoice,
      );

      expect(selectedTheme.companyName, companyTheme.companyName);
      expect(selectedTheme.companyCode, companyTheme.companyCode);
      expect(selectedTheme.logoUrl, companyTheme.logoUrl);
      expect(selectedTheme.isCompanyTheme, isTrue);
      expect(selectedTheme.primaryColor, isNot(companyTheme.primaryColor));
    });

    test('dark mode applies dark colors without loading-screen data', () {
      final selectedTheme = CompanyThemeService.applyThemeChoice(
        CompanyThemeData.standard,
        CompanyThemeService.darkThemeChoice,
      );

      expect(selectedTheme.isDark, isTrue);
      expect(selectedTheme.backgroundColor.computeLuminance(), lessThan(0.1));
      expect(selectedTheme.isCompanyTheme, isFalse);
    });

    test(
        'a custom dark background is treated as dark even when themeIsDark/themeMode was never set',
        () {
      // Mirrors a company (e.g. GENCYS) whose admin picked a custom dark
      // navy background/surface for branding but never separately toggled
      // an "is dark" flag -- previously this left isDark=false, so ink/icon
      // colors defaulted to light-theme values and became invisible against
      // the actual dark background.
      final resolved = CompanyThemeService.fromCompanyData({
        'name': 'Gencys',
        'code': 'GENCYS',
        'themeSource': 'manual',
        'themeEnabled': true,
        'themeBackgroundColor': '#020B12',
        'themeSurfaceColor': '#071A24',
      });

      expect(resolved.isDark, isTrue);
      expect(
        resolved.backgroundColor.computeLuminance(),
        lessThan(0.1),
      );
      expect(
        _contrastRatio(resolved.backgroundColor, resolved.inkColor),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance() + 0.05;
  final lb = b.computeLuminance() + 0.05;
  return la > lb ? la / lb : lb / la;
}
