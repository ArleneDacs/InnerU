import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:selfcare_projects/src/features/abundance/theme/abundance_assets.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';

/// The ambient artwork behind the Quests screens, ported from A12's
/// `PageBackdrop` (`src/components/ui/scene.tsx`).
///
/// A12 carries this behind its entire authenticated shell; the design spec's
/// "Image assets" section deliberately narrows it to the Quests screens
/// themselves, because the shared shell chrome is used by every company.
///
/// Same three layers as the reference, with A12's own dark-theme values from
/// `globals.css`: the plate at `--page-backdrop-opacity: 0.52`, blurred by
/// `--page-backdrop-blur: 5px` and scaled 1.08 so the blur has no soft edge to
/// show, then `--page-backdrop-veil` over it. The veil is the load-bearing
/// part — it is what keeps copy that is not sitting on a panel legible.
class AbundanceBackdrop extends StatelessWidget {
  const AbundanceBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform.scale(
                    scale: 1.08,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Opacity(
                        opacity: 0.52,
                        child: Image.asset(
                          abundanceBackdropAsset,
                          fit: BoxFit.cover,
                          alignment: const Alignment(0, 0.1),
                        ),
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x80080C1C),
                          Color(0xA8080C1C),
                          Color(0xBD080C1C),
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// A quest card's category scene, ported from A12's `Scene`
/// (`src/components/ui/scene.tsx`) as used by `rpg/quest-card.tsx`.
///
/// Two jobs, exactly as the reference documents them:
///
/// 1. Artwork is optional. [abundanceQuestSceneAsset] returns `null` for any
///    category with no plate, and this paints a category-tinted wash instead,
///    so no surface is ever blank.
/// 2. Copy stays legible. The `card` scrim variant washes upward from the
///    foot (A12's `--scene-scrim-card`, dark values), which is what lets
///    quest titles and badges sit straight on the art.
///
/// Purely decorative — wrapped in [IgnorePointer], never in the semantics
/// tree.
class AbundanceQuestScene extends StatelessWidget {
  const AbundanceQuestScene({super.key, required this.categoryCode});

  /// A `GoalCategory.code` value, e.g. `'PERSONAL'`.
  final String categoryCode;

  @override
  Widget build(BuildContext context) {
    final asset = abundanceQuestSceneAsset(categoryCode);
    final tint = AbundanceColors.categoryColor(categoryCode);

    return IgnorePointer(
      child: ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (asset != null)
              Image.asset(asset, fit: BoxFit.cover)
            else
              // A12's CSS fallback: a light shaft over a tinted ground.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: 0.30),
                      AbundanceColors.surfaceSunken,
                    ],
                  ),
                ),
              ),
            // `--scene-scrim-card`, .dark block: to top, from 0.97 at the
            // foot up to 0.30 at the head.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xF7080C1C),
                    Color(0xE6080C1C),
                    Color(0x80080C1C),
                    Color(0x4D080C1C),
                  ],
                  stops: [0.0, 0.3, 0.62, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
