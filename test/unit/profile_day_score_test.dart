import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_day_score.dart';

void main() {
  group('resolveDayScorePercent', () {
    test('returns the stored integer score as-is', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 20}),
        20,
      );
    });

    test('rounds a fractional score', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 82.6}),
        83,
      );
    });

    test('clamps a score above 100', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 140}),
        100,
      );
    });

    test('clamps a negative score to 0', () {
      expect(
        resolveDayScorePercent({'userTotalScore': -5}),
        0,
      );
    });

    test('defaults to 0 when the key is missing', () {
      expect(
        resolveDayScorePercent(<String, dynamic>{}),
        0,
      );
    });

    test('defaults to 0 when the value is not numeric', () {
      expect(
        resolveDayScorePercent({'userTotalScore': 'not-a-number'}),
        0,
      );
    });
  });
}
