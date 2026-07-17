# Goals Hub Mobile Restyle (Dark A12)

**Date:** 2026-07-18
**Status:** Approved
**Scope:** `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` only

## Goal

Restyle the Abundance 12 Goals Hub — the screen A12 company members see in the
Todo List tab — from its current shrunken-web-dashboard look into a polished,
mobile-native layout, while keeping the dark-navy + gold A12 brand.

**Content is frozen.** Every string, data value, stream, route, filter, and
behavior stays identical. No changes to `GoalDetailScreen`, `GoalFormScreen`,
services, domain, or scoring.

Two deliberate non-visual exceptions, both required to make the existing
widget test (`test/widget/abundance/goals_hub_screen_test.dart`) pass:

1. Goal-card titles render **as-authored** instead of through
   `.toUpperCase()` (the test expects `Run 100 km`, the card renders
   `RUN 100 KM`).
2. `_resolveAccess` reads `users/{uid}` through the injected
   `GoalsService.firestore` and parses it with the pure static
   `CompanyMembershipService.fromUserData`, instead of calling
   `CompanyMembershipService.loadForUser` (which is hardwired to the
   `FirebaseFirestore.instance` singleton and errors in widget tests, making
   the hub render the access-denied screen). Production reads the same
   document with the same parsing; only the instance is injectable now.

## Design

### 1. Atmosphere
- Background becomes a subtle vertical gradient: deep indigo `#0A1130` at the
  top fading to the existing `#050714`.
- Cards keep `#111A45` fill; borders soften slightly (lower-alpha `#27336C`).

### 2. Header
- "MY GOALS": 26px Georgia w800 (down from 34).
- Subtitle: 14.5px (down from 19), same copy.
- "New goal": compact gold pill (`#F0B93C`, black foreground), same label and
  `Icons.add`. Same stacked-vs-row responsive behavior at narrow widths.

### 3. Score hero
- Replace the 250px ring card with a compact horizontal card:
  - Left: ~120px ring, same pink score color (`#FF6B86`), rounded stroke caps,
    soft pink glow; score number + "of 100" centered inside.
  - Right: "Goal Total Score" (Georgia) and the existing description copy.
- Same strings throughout.

### 4. Metric tiles
- The four 130px-tall cards become compact stat tiles: 2×2 grid on phones,
  4-across on wide layouts.
- Tile anatomy: small tinted icon chip, 24px value, 11px letter-spaced
  uppercase label.
- Same labels (TOTAL GOALS / COMPLETED / IN PROGRESS / OVERDUE), same icons,
  same green accent (`#63E0B7`) on the completed value.

### 5. Category chips
- Same labels and counts, same "All" + three categories.
- Shorter pills; count rendered in a dimmer tone beside the label.
- Selected state stays gold-bordered/gold-text.

### 6. Goal cards
- New: category-colored left accent bar (uses `category.accent`).
- Badges tightened to 12px; same four badges (category, status, score, rank).
- Title: 17px Georgia w800, **as-authored case** (no `.toUpperCase()`).
- Description: 13.5px, same 3-line clamp.
- Progress: number sits inline beside a full-width 8px bar (same
  status-driven color logic: green completed, pink overdue, gold otherwise).
- Footer row (date • days-left/overdue label • tasks label) unchanged.
- Responsive 1/2/3-column `Wrap` layout preserved.

### 7. Empty & access-denied states
- Same strings; typography and spacing brought in line with the new scale.

## Verification

1. `flutter test test/widget/abundance/goals_hub_screen_test.dart` — currently
   red on the title-case assertion; must pass after the restyle.
2. `flutter analyze lib/src/features/abundance/screens/mentee/goals_hub_screen.dart`
   — clean.
3. Manual: hub renders correctly at phone width (1 column) and tablet width
   (2–3 columns) with goals present and with none (empty state).

## Non-goals

- No string/copy changes, no new features, no data or scoring changes.
- No theming plumbing changes (screen stays hardcoded dark A12, per decision).
- No changes to goal detail, goal form, dashboard entry card, or hub route.
