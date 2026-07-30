import 'package:flutter/material.dart';

/// Visual tokens for the Abundance-gated Quests redesign, ported verbatim
/// from `A12-Tracker/src/app/globals.css`'s `.dark` block — dark is A12's
/// real theme (its own CSS comment: "Dark is the real theme... Light is a
/// warm parchment counterpart"), consistent with the earlier rejected
/// light-theme attempt for this same feature. Every value here must trace
/// back to that file; do not invent new colors here.
class AbundanceColors {
  const AbundanceColors._();

  static const Color background = Color(0xFF080C1C);
  static const Color surfaceRaised = Color(0xFF0D1330);
  static const Color surfaceSunken = Color(0xFF060916);
  static const Color border = Color(0xFF1C2650);
  static const Color foreground = Color(0xFFF2ECD8);
  static const Color muted = Color(0xFF9FA8C9);

  static const Color primaryGold = Color(0xFFEAB73F);
  static const Color accentCyan = Color(0xFF58C8FF);

  static const Color scoreExcellent = Color(0xFF5EE6A8);
  static const Color scoreGood = Color(0xFF58C8FF);
  static const Color scoreWarning = Color(0xFFEAB73F);
  static const Color scoreCritical = Color(0xFFF0607A);

  static const Color categoryPersonal = Color(0xFF5EE6A8);
  static const Color categoryProfessional = Color(0xFFA98BFF);
  static const Color categoryContribution = Color(0xFF58C8FF);

  static const Map<String, Color> _categoryColors = {
    'PERSONAL': categoryPersonal,
    'PROFESSIONAL': categoryProfessional,
    'CONTRIBUTION': categoryContribution,
  };

  /// [categoryCode] is a `GoalCategory.code` value (e.g. `'PERSONAL'`).
  static Color categoryColor(String categoryCode) =>
      _categoryColors[categoryCode] ?? muted;

  /// A12's four score bands: >=80 excellent, >=60 good, >=40 warning, else
  /// critical (matches the score-color naming in `globals.css`; exact
  /// thresholds confirmed against `goal-score-badge.tsx` during Task 9).
  static Color scoreColorFor(num score) {
    if (score >= 80) return scoreExcellent;
    if (score >= 60) return scoreGood;
    if (score >= 40) return scoreWarning;
    return scoreCritical;
  }
}
