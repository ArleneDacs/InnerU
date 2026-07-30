import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';

void main() {
  test('category color map has all three categories, matching A12 exactly', () {
    expect(AbundanceColors.categoryColor('PERSONAL'), const Color(0xFF5EE6A8));
    expect(AbundanceColors.categoryColor('PROFESSIONAL'), const Color(0xFFA98BFF));
    expect(AbundanceColors.categoryColor('CONTRIBUTION'), const Color(0xFF58C8FF));
  });

  test('score color map covers all four bands', () {
    expect(AbundanceColors.scoreColorFor(95), AbundanceColors.scoreExcellent);
    expect(AbundanceColors.scoreColorFor(65), AbundanceColors.scoreGood);
    expect(AbundanceColors.scoreColorFor(40), AbundanceColors.scoreWarning);
    expect(AbundanceColors.scoreColorFor(10), AbundanceColors.scoreCritical);
  });

  test('core palette matches A12-Tracker globals.css .dark block', () {
    expect(AbundanceColors.background, const Color(0xFF080C1C));
    expect(AbundanceColors.surfaceRaised, const Color(0xFF0D1330));
    expect(AbundanceColors.surfaceSunken, const Color(0xFF060916));
    expect(AbundanceColors.border, const Color(0xFF1C2650));
    expect(AbundanceColors.foreground, const Color(0xFFF2ECD8));
    expect(AbundanceColors.muted, const Color(0xFF9FA8C9));
    expect(AbundanceColors.primaryGold, const Color(0xFFEAB73F));
    expect(AbundanceColors.accentCyan, const Color(0xFF58C8FF));
  });
}
