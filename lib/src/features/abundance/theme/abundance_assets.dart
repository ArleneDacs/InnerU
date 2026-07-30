/// Image asset paths for the Abundance Quests redesign, ported from
/// `A12-Tracker/src/components/ui/rank-medal.tsx` (`RANK_SRC`) and
/// `A12-Tracker/src/components/ui/scene.tsx` (`SCENES`). A12 collapses its
/// 10 rank keys onto 5 actual image files — this mirrors that exact
/// many-to-one mapping rather than commissioning new art for the collapsed
/// tiers.
const String _ranksBase = 'assets/images/abundance/ranks';
const String _scenesBase = 'assets/images/abundance/scenes';

const Map<String, String> _rankMedalAssets = {
  'HERALD': '$_ranksBase/archon.png',
  'GUARDIAN': '$_ranksBase/archon.png',
  'CRUSADER': '$_ranksBase/archon.png',
  'ARCHON': '$_ranksBase/archon.png',
  'LEGEND': '$_ranksBase/legend.png',
  'ANCIENT': '$_ranksBase/ancient.png',
  'DIVINE': '$_ranksBase/divine.png',
  'IMMORTAL': '$_ranksBase/immortal.png',
  'MASTER_IMMORTAL': '$_ranksBase/immortal.png',
  'TITAN': '$_ranksBase/immortal.png',
};

/// [rankKey] is a `GoalRank.key` value. Falls back to `archon.png` (the
/// lowest-tier art) for any key not in the current 10-tier ladder rather
/// than throwing, since this is purely decorative.
String abundanceRankMedalAsset(String rankKey) =>
    _rankMedalAssets[rankKey] ?? '$_ranksBase/archon.png';

const Map<String, String> _questSceneAssets = {
  'PERSONAL': '$_scenesBase/quest-personal.webp',
  'PROFESSIONAL': '$_scenesBase/quest-professional.webp',
  'CONTRIBUTION': '$_scenesBase/quest-contribution.webp',
};

/// [categoryCode] is a `GoalCategory.code` value. Returns `null` for
/// anything outside the three known categories so callers can fall back to
/// a plain tinted background instead of crashing.
String? abundanceQuestSceneAsset(String categoryCode) =>
    _questSceneAssets[categoryCode];

/// The ambient backdrop art used behind the Quests screens (not the whole
/// app shell — see the design spec's "Image assets" section for why).
const String abundanceBackdropAsset = '$_scenesBase/hero-dark.webp';
