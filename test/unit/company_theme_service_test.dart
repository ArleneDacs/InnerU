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
  });
}
