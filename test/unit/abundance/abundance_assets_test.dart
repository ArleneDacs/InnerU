import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_assets.dart';

void main() {
  group('abundanceRankMedalAsset', () {
    test('collapses the bottom four tiers onto archon.png', () {
      for (final key in ['HERALD', 'GUARDIAN', 'CRUSADER', 'ARCHON']) {
        expect(abundanceRankMedalAsset(key),
            'assets/images/abundance/ranks/archon.png');
      }
    });

    test('collapses the top three tiers onto immortal.png', () {
      for (final key in ['IMMORTAL', 'MASTER_IMMORTAL', 'TITAN']) {
        expect(abundanceRankMedalAsset(key),
            'assets/images/abundance/ranks/immortal.png');
      }
    });

    test('legend, ancient, and divine each have their own asset', () {
      expect(abundanceRankMedalAsset('LEGEND'),
          'assets/images/abundance/ranks/legend.png');
      expect(abundanceRankMedalAsset('ANCIENT'),
          'assets/images/abundance/ranks/ancient.png');
      expect(abundanceRankMedalAsset('DIVINE'),
          'assets/images/abundance/ranks/divine.png');
    });

    test('unknown keys fall back to archon.png rather than throwing', () {
      expect(abundanceRankMedalAsset('SOMETHING_NEW'),
          'assets/images/abundance/ranks/archon.png');
    });
  });

  group('abundanceQuestSceneAsset', () {
    test('maps each category to its own scene', () {
      expect(abundanceQuestSceneAsset('PERSONAL'),
          'assets/images/abundance/scenes/quest-personal.webp');
      expect(abundanceQuestSceneAsset('PROFESSIONAL'),
          'assets/images/abundance/scenes/quest-professional.webp');
      expect(abundanceQuestSceneAsset('CONTRIBUTION'),
          'assets/images/abundance/scenes/quest-contribution.webp');
    });

    test('unknown categories return null rather than throwing', () {
      expect(abundanceQuestSceneAsset('UNKNOWN'), isNull);
    });
  });

  test('backdrop asset points at the hero-dark plate', () {
    expect(abundanceBackdropAsset, 'assets/images/abundance/scenes/hero-dark.webp');
  });
}
