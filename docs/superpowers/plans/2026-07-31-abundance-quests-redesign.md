# Abundance Quests Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild InnerU's Abundance-exclusive Quests feature (mentee Quests hub/detail/creation-wizard, a new coach Quests roster, and a custom app shell) to match `A12-Tracker`'s actual rendered UI exactly, gated to members of the Abundance company only.

**Architecture:** One shared gating helper replaces three drifting company-detection heuristics. Existing screens (`goals_hub_screen.dart`, `goal_detail_screen.dart`) are restyled in place — their class structure already mirrors A12's sections closely. `goal_form_screen.dart` is rewritten from a single-page form into a 4-step wizard. A new coach roster screen and backend endpoint are added. A new `AbundanceShellScreen` (custom header + 5-tab bottom nav) wraps all of it and is spliced into the existing `Setuppage`/`CoachSetuppage` widgets at the point where they already resolve the user's company theme.

**Tech Stack:** Flutter/Dart (client), Laravel/PostgreSQL (backend API), `flutter_test` + `fake_cloud_firestore` (Flutter tests), PHPUnit (backend tests).

## Global Constraints

- Gating condition, exact: `code.trim().toUpperCase() == 'ABU15DN' || name.trim().toUpperCase() == 'ABUNDANCE'` (from the spec's "Scope condition").
- Every other company must see zero behavior change — no new conditional may run for them beyond the existing pass-through case.
- Colors come only from `abundance_theme.dart` (Task 3) — no new magic hex literals in screen files.
- Terminology for Abundance-gated screens: Goal → Quest, Goals hub → Quests, Overall/Goal Total Score → Life Power (per the spec's terminology table). Every other company keeps "Goals"/"Overall Score" — these are UI strings only; no domain/model renames.
- `lib/src/features/abundance/domain/` stays pure Dart (no Flutter/Firestore imports) — new UI-facing constants (colors, asset paths) go in a new `lib/src/features/abundance/theme/` folder instead, not in `domain/`.
- No commits are made automatically as part of this plan's steps — the user handles all git commits themselves. Steps below say "stage the change" rather than "commit."

---

## Task 1: Abundance company gate helper

**Files:**
- Create: `lib/src/features/abundance/domain/abundance_company.dart`
- Test: `test/unit/abundance/abundance_company_test.dart`

**Interfaces:**
- Produces: `AbundanceCompany.matches(String? code, String? name) -> bool`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';

void main() {
  group('AbundanceCompany.matches', () {
    test('matches the exact code, case-insensitively and trimmed', () {
      expect(AbundanceCompany.matches('ABU15DN', 'Some Other Name'), isTrue);
      expect(AbundanceCompany.matches('abu15dn', 'Some Other Name'), isTrue);
      expect(AbundanceCompany.matches('  ABU15DN  ', 'Some Other Name'), isTrue);
    });

    test('matches the exact name, case-insensitively and trimmed', () {
      expect(AbundanceCompany.matches('OTHERCODE', 'Abundance'), isTrue);
      expect(AbundanceCompany.matches('OTHERCODE', 'abundance'), isTrue);
      expect(AbundanceCompany.matches('OTHERCODE', '  ABUNDANCE  '), isTrue);
    });

    test('does not match near-miss codes or names', () {
      expect(AbundanceCompany.matches('A12', 'Abundance 12'), isFalse);
      expect(AbundanceCompany.matches('AB12X', 'Abundance 12'), isFalse);
      expect(AbundanceCompany.matches('ABU15DNX', 'Not Abundance'), isFalse);
      expect(AbundanceCompany.matches(null, null), isFalse);
      expect(AbundanceCompany.matches('', ''), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/abundance/abundance_company_test.dart`
Expected: FAIL — `abundance_company.dart` doesn't exist yet (import error).

- [ ] **Step 3: Write the implementation**

```dart
/// Whether a company (by its InnerU `code`/`name` fields) is the Abundance
/// company this Quests redesign is scoped to. This is the single source of
/// truth for that check — see the design spec's "Existing gating bug"
/// section for why three separate ad hoc heuristics used to answer this
/// question differently.
class AbundanceCompany {
  const AbundanceCompany._();

  static bool matches(String? code, String? name) {
    final normalizedCode = (code ?? '').trim().toUpperCase();
    final normalizedName = (name ?? '').trim().toUpperCase();
    return normalizedCode == 'ABU15DN' || normalizedName == 'ABUNDANCE';
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/abundance/abundance_company_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Stage the change**

```bash
git add lib/src/features/abundance/domain/abundance_company.dart test/unit/abundance/abundance_company_test.dart
```

---

## Task 2: Consolidate the three existing gating heuristics

**Files:**
- Modify: `lib/src/features/authentication/screen/todo_list.dart:682-696`
- Modify: `lib/src/services/company_theme_service.dart` (the `_matchesAbundance12` static method)
- Modify: `lib/src/features/authentication/screen/company_loading/company_loading_screen.dart:897-909`

**Interfaces:**
- Consumes: `AbundanceCompany.matches(String?, String?)` from Task 1.

This task fixes the real bug described in the spec: none of these three existing checks (which all require `"12"` somewhere in the code/name) match a company whose real code is `ABU15DN` and name is exactly `ABUNDANCE`.

- [ ] **Step 1: Add the import to all three files**

In each of the three files, add near the top:

```dart
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
```

- [ ] **Step 2: Replace `todo_list.dart`'s `_isAbundance12Company`**

Find (around line 682):

```dart
  bool _isAbundance12Company(CompanyMembership? membership) {
    final companyName = membership?.name ?? '';
    final companyCode = membership?.code ?? '';
    final normalizedName =
        companyName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normalizedCode =
        companyCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return normalizedName.contains('abundance12') ||
        (normalizedName.contains('abundance') &&
            normalizedName.contains('12')) ||
        normalizedCode.contains('ABUNDANCE12') ||
        normalizedCode.contains('ABUND12') ||
        normalizedCode == 'A12' ||
        normalizedCode.startsWith('AB12');
  }
```

Replace with:

```dart
  bool _isAbundance12Company(CompanyMembership? membership) {
    return AbundanceCompany.matches(membership?.code, membership?.name);
  }
```

- [ ] **Step 3: Replace `company_theme_service.dart`'s `_matchesAbundance12`**

Find the static method (identical body/shape to the one above, just `static`):

```dart
  static bool _matchesAbundance12(String companyName, String companyCode) {
    final normalizedName = ...
    ...
  }
```

Replace with:

```dart
  static bool _matchesAbundance12(String companyName, String companyCode) {
    return AbundanceCompany.matches(companyCode, companyName);
  }
```

(Leave `_matchesGencys` and `_matchesIamPlus` untouched — they're unrelated companies.)

- [ ] **Step 4: Replace `company_loading_screen.dart`'s `_matchesAbundance12`**

Find, around line 897 (instance method on `_CompanyLoadingGateState`):

```dart
  bool _matchesAbundance12(String companyName, String companyCode) {
    final normalizedName = ...
    ...
  }
```

Replace with:

```dart
  bool _matchesAbundance12(String companyName, String companyCode) {
    return AbundanceCompany.matches(companyCode, companyName);
  }
```

- [ ] **Step 5: Run the existing test suite to confirm nothing broke**

Run: `flutter test test/widget/abundance/ test/unit/abundance/`
Expected: same pass/fail counts as before this task (this is a pure refactor of matching logic, not new behavior — the known-failing tests listed in the spec are still expected to fail here; they're fixed in Tasks 9/10).

- [ ] **Step 6: Stage the change**

```bash
git add lib/src/features/authentication/screen/todo_list.dart lib/src/services/company_theme_service.dart lib/src/features/authentication/screen/company_loading/company_loading_screen.dart
```

---

## Task 3: Abundance visual theme tokens

**Files:**
- Create: `lib/src/features/abundance/theme/abundance_theme.dart`
- Test: `test/unit/abundance/abundance_theme_test.dart`

**Interfaces:**
- Produces: `AbundanceColors` class with static `Color`/`Map` constants used by every later screen task.

- [ ] **Step 1: Write the failing test**

```dart
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/abundance/abundance_theme_test.dart`
Expected: FAIL — file doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/abundance/abundance_theme_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Stage the change**

```bash
git add lib/src/features/abundance/theme/abundance_theme.dart test/unit/abundance/abundance_theme_test.dart
```

---

## Task 4: Image assets + asset path maps

**Files:**
- Create (binary copies): `assets/images/abundance/ranks/archon.png`, `assets/images/abundance/ranks/legend.png`, `assets/images/abundance/ranks/ancient.png`, `assets/images/abundance/ranks/divine.png`, `assets/images/abundance/ranks/immortal.png`, `assets/images/abundance/scenes/quest-personal.webp`, `assets/images/abundance/scenes/quest-professional.webp`, `assets/images/abundance/scenes/quest-contribution.webp`, `assets/images/abundance/scenes/hero-dark.webp`
- Modify: `pubspec.yaml`
- Create: `lib/src/features/abundance/theme/abundance_assets.dart`
- Test: `test/unit/abundance/abundance_assets_test.dart`

**Interfaces:**
- Consumes: `GoalRank.key` strings from `lib/src/features/abundance/domain/domain.dart` (`'HERALD'`, `'GUARDIAN'`, `'CRUSADER'`, `'ARCHON'`, `'LEGEND'`, `'ANCIENT'`, `'DIVINE'`, `'IMMORTAL'`, `'MASTER_IMMORTAL'`, `'TITAN'`); `GoalCategory.code` strings (`'PERSONAL'`, `'PROFESSIONAL'`, `'CONTRIBUTION'`).
- Produces: `abundanceRankMedalAsset(String rankKey) -> String`, `abundanceQuestSceneAsset(String categoryCode) -> String?`, `abundanceBackdropAsset` (a `String` constant).

- [ ] **Step 1: Copy the asset files**

```bash
mkdir -p assets/images/abundance/ranks assets/images/abundance/scenes
cp A12-Tracker/public/ranks/archon.png assets/images/abundance/ranks/archon.png
cp A12-Tracker/public/ranks/legend.png assets/images/abundance/ranks/legend.png
cp A12-Tracker/public/ranks/ancient.png assets/images/abundance/ranks/ancient.png
cp A12-Tracker/public/ranks/divine.png assets/images/abundance/ranks/divine.png
cp A12-Tracker/public/ranks/immortal.png assets/images/abundance/ranks/immortal.png
cp A12-Tracker/public/scenes/quest-personal.webp assets/images/abundance/scenes/quest-personal.webp
cp A12-Tracker/public/scenes/quest-professional.webp assets/images/abundance/scenes/quest-professional.webp
cp A12-Tracker/public/scenes/quest-contribution.webp assets/images/abundance/scenes/quest-contribution.webp
cp A12-Tracker/public/scenes/hero-dark.webp assets/images/abundance/scenes/hero-dark.webp
```

- [ ] **Step 2: Register the new folders in `pubspec.yaml`**

Find the `assets:` list (around line 123-129):

```yaml
  assets:
    - assets/images/
    - assets/images/login-image/
    - assets/logo/
    - assets/audio/
    - assets/videos/
```

Add two lines (Flutter doesn't include subdirectories automatically, hence the two explicit entries, matching how `assets/images/login-image/` is already handled):

```yaml
  assets:
    - assets/images/
    - assets/images/login-image/
    - assets/images/abundance/ranks/
    - assets/images/abundance/scenes/
    - assets/logo/
    - assets/audio/
    - assets/videos/
```

- [ ] **Step 3: Write the failing test**

```dart
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
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/unit/abundance/abundance_assets_test.dart`
Expected: FAIL — file doesn't exist yet.

- [ ] **Step 5: Write the implementation**

```dart
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
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/unit/abundance/abundance_assets_test.dart`
Expected: PASS (8 tests).

- [ ] **Step 7: Run `flutter pub get` so the new asset folders take effect**

Run: `flutter pub get`
Expected: completes without error.

- [ ] **Step 8: Stage the change**

```bash
git add assets/images/abundance pubspec.yaml lib/src/features/abundance/theme/abundance_assets.dart test/unit/abundance/abundance_assets_test.dart
```

---

## Task 5: Backend coach goals roster endpoint

**Files:**
- Modify: `backend/app/Http/Controllers/Api/GoalController.php` (add a method; `CoachMentee` is already imported at the top of this file)
- Modify: `backend/routes/api.php` (add a route near the existing `coach/mentees/{menteeId}/goals` line, ~143)
- Test: `backend/tests/Feature/CoachGoalsRosterTest.php`

**Interfaces:**
- Produces: `GET /api/coach/goals` → `{"roster": [{"menteeId": "...", "menteeName": "...", "goals": [{"id","title","category","status","progress","targetDate"}, ...]}, ...]}`, authenticated via Sanctum, scoped to the requesting coach's own `coach_mentees` rows.

- [ ] **Step 1: Write the failing test**

```php
<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\CoachMentee;
use App\Models\Goal;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CoachGoalsRosterTest extends TestCase
{
    use RefreshDatabase;

    public function test_roster_groups_goals_by_mentee_for_the_requesting_coach(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Abundance',
            'code' => 'ABU15DN',
        ]);

        $coach = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);
        $mentee = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);
        $otherMentee = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);

        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'mentee_name' => 'Maychell Alcorin',
        ]);

        Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $mentee->id,
            'company_id' => $company->id,
            'category' => 'PERSONAL',
            'title' => 'Run 100 km',
            'status' => 'IN_PROGRESS',
            'progress' => 40,
            'goal_type' => 'MERIT',
            'target_period' => 'NONE',
            'direction' => 'GAIN',
            'target_value' => 100,
            'current_value' => 40,
            'unit' => 'km',
            'start_date' => '2026-07-01',
            'target_date' => '2026-09-01',
        ]);

        // A goal belonging to a mentee this coach does NOT have an active
        // assignment for must never appear in the roster.
        Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $otherMentee->id,
            'company_id' => $company->id,
            'category' => 'PROFESSIONAL',
            'title' => 'Should not appear',
            'status' => 'NOT_STARTED',
            'progress' => 0,
            'goal_type' => 'MERIT',
            'target_period' => 'NONE',
            'direction' => 'GAIN',
            'target_value' => 10,
            'current_value' => 0,
            'unit' => 'pts',
            'start_date' => '2026-07-01',
            'target_date' => '2026-09-01',
        ]);

        Sanctum::actingAs($coach);

        $response = $this->getJson('/api/coach/goals');

        $response->assertOk();
        $roster = $response->json('roster');
        $this->assertCount(1, $roster);
        $this->assertSame('Maychell Alcorin', $roster[0]['menteeName']);
        $this->assertCount(1, $roster[0]['goals']);
        $this->assertSame('Run 100 km', $roster[0]['goals'][0]['title']);
    }

    public function test_roster_is_empty_for_a_coach_with_no_mentees(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Abundance',
            'code' => 'ABU15DN',
        ]);
        $coach = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);
        Sanctum::actingAs($coach);

        $response = $this->getJson('/api/coach/goals');

        $response->assertOk();
        $this->assertSame([], $response->json('roster'));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && vendor/bin/phpunit tests/Feature/CoachGoalsRosterTest.php`
Expected: FAIL — route `/api/coach/goals` doesn't exist yet (404).

- [ ] **Step 3: Add the controller method**

In `backend/app/Http/Controllers/Api/GoalController.php`, add this new public method (anywhere among the other public methods, e.g. right after `index()`):

```php
    public function coachGoalsRoster(Request $request): JsonResponse
    {
        $user = $this->currentUser($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $assignments = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->get(['mentee_id', 'mentee_name'])
            ->unique('mentee_id')
            ->values();

        $menteeIds = $assignments->pluck('mentee_id')->all();

        $goalsByMentee = Goal::query()
            ->whereIn('user_id', $menteeIds)
            ->orderByDesc('updated_at')
            ->get()
            ->groupBy('user_id');

        $roster = $assignments->map(function (CoachMentee $assignment) use ($goalsByMentee) {
            $goals = $goalsByMentee->get($assignment->mentee_id, collect());

            return [
                'menteeId' => (string) $assignment->mentee_id,
                'menteeName' => $assignment->mentee_name,
                'goals' => $goals->map(fn (Goal $goal) => [
                    'id' => (string) $goal->id,
                    'title' => $goal->title,
                    'category' => $goal->category,
                    'status' => $goal->status,
                    'progress' => (int) $goal->progress,
                    'targetDate' => $goal->target_date?->toIso8601String(),
                ])->values(),
            ];
        });

        return response()->json(['roster' => $roster->values()]);
    }
```

- [ ] **Step 4: Register the route**

In `backend/routes/api.php`, near the existing line (~143) `Route::get('/coach/mentees/{menteeId}/goals', [CoachManagementController::class, 'menteeGoals']);`, add:

```php
    Route::get('/coach/goals', [GoalController::class, 'coachGoalsRoster']);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && vendor/bin/phpunit tests/Feature/CoachGoalsRosterTest.php`
Expected: PASS (2 tests). (Use `vendor/bin/phpunit` directly, not `php artisan test --configuration=`, which is known broken — see [[postgres-ci-and-scoring-bug]].)

- [ ] **Step 6: Run the full backend suite to confirm nothing else broke**

Run: `cd backend && vendor/bin/phpunit`
Expected: same pass count as before, plus these 2 new passing tests.

- [ ] **Step 7: Stage the change**

```bash
git add backend/app/Http/Controllers/Api/GoalController.php backend/routes/api.php backend/tests/Feature/CoachGoalsRosterTest.php
```

---

## Task 6: Flutter coach roster service method + model

**Files:**
- Modify: `lib/src/features/abundance/services/goals_service.dart` (add a model class + a method to `GoalsService`)
- Test: `test/unit/abundance/goals_service_coach_roster_test.dart`

**Interfaces:**
- Consumes: `GET /api/coach/goals` contract from Task 5; existing `GoalSummary.fromJson` (already defined in this file).
- Produces: `CoachMenteeGoals { menteeId, menteeName, goals }`, `GoalsService.fetchCoachGoalsRoster() -> Future<List<CoachMenteeGoals>>`.

- [ ] **Step 1: Write the failing test**

This tests the JSON-parsing logic directly (the same scope of coverage the file's other `_api`-backed read methods currently have — none of them are covered by network-level tests either, since `ApiClient` has no test seam for mocking HTTP in this codebase yet):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  test('CoachMenteeGoals.fromJson parses a roster entry', () {
    final entry = CoachMenteeGoals.fromJson({
      'menteeId': '42',
      'menteeName': 'Maychell Alcorin',
      'goals': [
        {
          'id': 'g1',
          'userId': '42',
          'companyId': 'c1',
          'title': 'Run 100 km',
          'description': null,
          'notes': null,
          'status': 'IN_PROGRESS',
          'progress': 40,
          'category': 'PERSONAL',
          'goalType': 'MERIT',
          'targetPeriod': 'NONE',
          'direction': 'GAIN',
          'targetValue': 100,
          'currentValue': 40,
          'unit': 'km',
          'startDate': '2026-07-01T00:00:00.000Z',
          'targetDate': '2026-09-01T00:00:00.000Z',
          'completedAt': null,
        },
      ],
    });

    expect(entry.menteeId, '42');
    expect(entry.menteeName, 'Maychell Alcorin');
    expect(entry.goals, hasLength(1));
    expect(entry.goals.single.title, 'Run 100 km');
  });

  test('CoachMenteeGoals.fromJson tolerates a missing goals list', () {
    final entry = CoachMenteeGoals.fromJson({
      'menteeId': '7',
      'menteeName': 'No Goals Yet',
    });

    expect(entry.goals, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/abundance/goals_service_coach_roster_test.dart`
Expected: FAIL — `CoachMenteeGoals` doesn't exist yet.

- [ ] **Step 3: Add the model and service method**

In `lib/src/features/abundance/services/goals_service.dart`, add this class near `GoalSummary` (top-level, alongside it):

```dart
/// One coach roster row: a mentee and their quests, as returned by
/// `GET /api/coach/goals`. Mirrors `A12-Tracker`'s `listMenteeGoals` shape.
class CoachMenteeGoals {
  const CoachMenteeGoals({
    required this.menteeId,
    required this.menteeName,
    required this.goals,
  });

  factory CoachMenteeGoals.fromJson(Map<String, dynamic> json) {
    final rawGoals = json['goals'];
    return CoachMenteeGoals(
      menteeId: json['menteeId']?.toString() ?? '',
      menteeName: json['menteeName']?.toString() ?? '',
      goals: rawGoals is List
          ? rawGoals
              .whereType<Map>()
              .map((g) => GoalSummary.fromJson(Map<String, dynamic>.from(g)))
              .toList()
          : const <GoalSummary>[],
    );
  }

  final String menteeId;
  final String menteeName;
  final List<GoalSummary> goals;
}
```

And add this method to the `GoalsService` class (alongside its other `_api`-backed read methods, e.g. near `_fetchGoals`):

```dart
  /// Every mentee this coach is assigned, each with their quests — the data
  /// backing the coach Quests roster screen. Read-only; coach visibility is
  /// enforced server-side against `coach_mentees`, mirroring how the
  /// per-mentee endpoint already works.
  Future<List<CoachMenteeGoals>> fetchCoachGoalsRoster() async {
    final response = await _api.getJson('/api/coach/goals', token: _token);
    final raw = response['roster'];
    if (raw is! List) return const <CoachMenteeGoals>[];
    return raw
        .whereType<Map>()
        .map((entry) => CoachMenteeGoals.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/abundance/goals_service_coach_roster_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the full existing abundance unit suite to confirm nothing broke**

Run: `flutter test test/unit/abundance/`
Expected: same pass/fail counts as before, plus these 2 new passing tests.

- [ ] **Step 6: Stage the change**

```bash
git add lib/src/features/abundance/services/goals_service.dart test/unit/abundance/goals_service_coach_roster_test.dart
```

---

## Task 7: Quest creation/edit wizard — Part A (scaffold + steps 1-2)

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goal_form_screen.dart` (currently a single-page form: `GoalFormScreen`, `_GoalFormScreenState`, `_GoalTypeCard`, `_ActionPlansPanel`)
- Test: `test/widget/abundance/goal_form_screen_test.dart` (rewritten)

Note on the spec's known-failing "Save goal" vs "Create goal" label test: that
test no longer applies conceptually. The wizard's step 4 button is "Submit"
for both create and edit (matching A12's own wizard, which doesn't
distinguish create/edit button text either), so there is no "Save goal" vs
"Create goal" label anywhere in the rewritten screen. Delete that old
assertion when rewriting the test file rather than trying to preserve it —
the underlying behavior it guarded (create vs. edit both work) is covered by
this task's and Task 8's new tests instead.

**Interfaces:**
- Consumes: `AbundanceColors` (Task 3), existing `GoalsService`, existing `domain.dart` enums (`GoalCategory`, `GoalDirection`, `TargetPeriod`).
- Produces: `GoalFormScreen` keeps its existing external constructor shape (callers in `goal_detail_screen.dart` and `goals_hub_screen.dart` are unaffected by this task), but its body becomes a 4-step wizard with an internal `_currentStep` (0-3). Later tasks (8) build on this; Tasks 9-10 call into this screen unchanged.

A12's reference is `A12-Tracker/src/app/(app)/goals/goal-wizard.tsx` (1,671 lines) — read that file's step 1 and step 2 sections directly for exact field order, labels, and validation copy; this task's job is the step *shell* (navigation between steps, progress bar, per-step validation gating) plus the first two steps' fields.

**The real existing file, confirmed by reading it, is:**

```dart
class GoalFormScreen extends StatefulWidget {
  const GoalFormScreen({super.key, required this.service, required this.uid, this.existing});
  final GoalsService service;
  final String uid;
  final GoalSummary? existing; // null = create, non-null = edit
}
```

with `_GoalFormScreenState` already holding `_title`, `_description`, `_notes`,
`_targetValue`, `_currentValue`, `_unit` (all `TextEditingController`s),
`_category` (currently `late GoalCategory`, defaulting to
`g?.category ?? GoalCategory.personal` — **change this to `GoalCategory?
_category` with no default**, since A12's wizard shows the category picker
unselected until chosen, and step 2 must be able to validate "nothing picked
yet"), `_goalType`, `_direction`, `_targetPeriod`, `_status`, `_startDate`,
`_targetDate` (defaults to `addDays(DateTime.now(), 90)` — **keep this
default as-is**; A12's screenshots show a "defaults to the Council deadline"
copy, but InnerU has no council-settings concept yet and building one is
out of scope here per the design spec, so the 90-day default stays), and
`_planTitles`. Keep all of these field names and the existing `_save()`
method (shown in full in Task 8, Step 3) — this task restructures how they're
*presented* (across 4 steps instead of 1 page), not what they're named or how
saving works.

- [ ] **Step 1: Write the failing test for step navigation**

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_form_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

void main() {
  testWidgets('wizard starts on step 1 of 4 and blocks Next until the declaration is filled',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 4 — What'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Still on step 1 — the declaration field is required and empty.
    expect(find.text('Step 1 of 4 — What'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      'I see myself finishing what I start',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 4 — How'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('step 2 requires a category and a target value before advancing',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      'I see myself finishing what I start',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // No category chosen yet — Next must not advance.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 — How'), findsOneWidget);

    await tester.tap(find.text('Personal'));
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '10');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 — When & qualities'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/goal_form_screen_test.dart`
Expected: FAIL — the current screen has no step concept at all (single page, different text).

- [ ] **Step 3: Rewrite the screen as a step wizard**

Rewrite `lib/src/features/abundance/screens/mentee/goal_form_screen.dart`'s `_GoalFormScreenState` around an explicit step index. Keep the existing top-level `GoalFormScreen` widget's constructor parameters exactly as they are today (do not change what `goal_detail_screen.dart`/`goals_hub_screen.dart` pass in). The core new state shape:

```dart
  // New field, added alongside the existing ones listed above:
  final _declarationController = TextEditingController();

  int _currentStep = 0; // 0=What, 1=How, 2=When & qualities, 3=Declaration
  static const _stepTitles = [
    'Step 1 of 4 — What',
    'Step 2 of 4 — How',
    'Step 3 of 4 — When & qualities',
    'Step 4 of 4 — Declaration',
  ];

  bool get _step1Valid => _declarationController.text.trim().length >= 3;
  bool get _step2Valid =>
      _category != null && double.tryParse(_targetValue.text.trim()) != null;

  void _goNext() {
    final valid = switch (_currentStep) {
      0 => _step1Valid,
      1 => _step2Valid,
      _ => true,
    };
    if (!valid) return;
    setState(() => _currentStep = (_currentStep + 1).clamp(0, 3));
  }

  void _goBack() {
    setState(() => _currentStep = (_currentStep - 1).clamp(0, 3));
  }

  // ... build() renders a AppBar-less header showing _stepTitles[_currentStep],
  // a 4-segment progress bar (compare goal-wizard.tsx's progress bar markup),
  // then the body for _currentStep via a switch, then a Back/Next (or
  // Back/Submit on step 4) row. Colors from AbundanceColors (Task 3):
  // background, surfaceRaised for cards, primaryGold for the active
  // progress segment and the Next/Submit button, border for inactive
  // segments and field outlines, foreground/muted for text.
```

(`_category`, `_targetValue`, `_direction`, `_targetPeriod`, and `_planTitles`
are the existing fields named in the box above — reuse them exactly, don't
introduce new ones. Change `_category`'s declaration from `late GoalCategory
_category` to `GoalCategory? _category`, and its `initState` line from
`_category = g?.category ?? GoalCategory.personal;` to `_category =
g?.category;` — an edit inherits its existing category as before, but a new
quest starts with none picked, matching A12's wizard.)

Step 0 ("What") body: an optional entry point button (see Step 5 below for why its action is deferred) followed by a required multiline `TextField` with `key: const Key('quest-declaration-field')`, controller `_declarationController`, and label text "What do you joyfully see yourself achieving?" (copied verbatim from `goal-wizard.tsx` step 1 — confirm exact copy there).

Step 1 ("How") body: a category picker (three tappable rows/chips labelled "Personal", "Professional", "Contribution" — tapping one sets `_category`), a Gain/Release direction toggle bound to `_direction`, the existing `_targetValue` `TextField` (add `key: const Key('quest-target-value-field')` to it), a target-period dropdown bound to `_targetPeriod`, and the optional action-plan list builder (reuse the existing `_ActionPlansPanel` widget already in this file, adapted to read from `_planTitles`, the existing field).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/abundance/goal_form_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Note the AI-suggestions button as a flagged gap, not a silent omission**

Render the "Get 5 AI suggestions" button visible in the screenshots on step 0 and step 2, wired to a `_requestAiSuggestions()` method that currently just shows a snackbar: `ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI suggestions are coming soon.')))`. Do not attempt to reverse-engineer or guess at real AI-suggestion behavior — the spec explicitly flagged this as unconfirmed from source. A later task (outside this plan) should read `A12-Tracker/src/app/(app)/goals/actions.ts` for the real behavior before wiring this up for real.

- [ ] **Step 6: Stage the change**

```bash
git add lib/src/features/abundance/screens/mentee/goal_form_screen.dart test/widget/abundance/goal_form_screen_test.dart
```

---

## Task 8: Quest creation/edit wizard — Part B (steps 3-4 + submit)

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goal_form_screen.dart` (continue Task 7's file)
- Test: `test/widget/abundance/goal_form_screen_test.dart` (extend)

**Interfaces:**
- Consumes: Task 7's `_currentStep`/field state; the existing `_save()` method already in this file (calls `widget.service.updateGoal(...)` when `_isEdit`, else `widget.service.createGoal(...)`, then `Navigator.of(context).pop()` — shown in full in Step 3 below). Task 7 must not have deleted or renamed this method.
- Produces: nothing new for later tasks — this completes the wizard.

- [ ] **Step 1: Write the failing test**

```dart
  testWidgets('completing all 4 steps and submitting creates the quest',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());
    await FakeFirebaseFirestore().collection('users').doc('u1').set({
      'companyId': 'c1',
    });

    await tester.pumpWidget(MaterialApp(
      home: GoalFormScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('quest-declaration-field')),
      'I see myself finishing what I start',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Personal'));
    await tester.enterText(find.byKey(const Key('quest-target-value-field')), '10');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 4 — When & qualities'), findsOneWidget);
    await tester.tap(find.text('Commitment'));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 4 of 4 — Declaration'), findsOneWidget);
    expect(find.textContaining('I see myself finishing what I start'), findsWidgets);
    expect(find.text('Commitment'), findsWidgets);

    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    // Submitting pops the wizard back to its caller.
    expect(find.byType(GoalFormScreen), findsNothing);
  });
```

(Append this test inside the existing `void main() { ... }` block from Task 7's test file, not as a second `main()`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/goal_form_screen_test.dart`
Expected: FAIL — steps 3/4 and the qualities picker don't exist yet.

- [ ] **Step 3: Add steps 2 and 3, and the submit action**

Step 2 ("When & qualities") body: reuse the existing `_targetDate` field and its existing `_pickTargetDate()` method (already in the file, shown in Task 7's box above) as the deadline picker — it already defaults to `addDays(DateTime.now(), 90)`, per Task 7's note that a real council-deadline default is out of scope here. Add two new fields to `_GoalFormScreenState`: `final Set<String> _qualities = {};` and `final _qualitiesFreeTextController = TextEditingController();`. Render a chip row of quality names ("Commitment", "Discipline", "Excellence", "Integrity", "Responsibility", "Love", "Compassion", "Awareness" — copied verbatim from the screenshots) toggling membership in `_qualities`, syncing `_qualitiesFreeTextController.text` to `_qualities.join(', ')` whenever a chip is toggled (and parsing typed text back into `_qualities` on submit, splitting on commas).

Step 3 ("Declaration") body: a read-only summary card showing `_declarationController.text` and `_qualities.join(', ')`, plus the Back/Submit row (replacing Back/Next on this last step).

Wire the Submit button to the existing `_save()` method unchanged:

```dart
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final targetValue = double.tryParse(_targetValue.text.trim()) ?? 0;
      final currentValue = double.tryParse(_currentValue.text.trim()) ?? 0;
      if (_isEdit) {
        await widget.service.updateGoal(
          goalId: widget.existing!.id,
          actorId: widget.uid,
          title: _title.text.trim(),
          description: _description.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          startDate: _startDate,
          targetDate: _targetDate,
          goalType: _goalType,
          direction: _direction,
          targetValue: targetValue,
          currentValue: currentValue,
          unit: _unit.text,
          targetPeriod: _targetPeriod,
          status: _status,
        );
      } else {
        await widget.service.createGoal(
          uid: widget.uid,
          category: _category!, // non-null: step 2 already validated this
          title: _title.text.trim(),
          description: _description.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          startDate: _startDate,
          targetDate: _targetDate,
          goalType: _goalType,
          direction: _direction,
          targetValue: targetValue,
          currentValue: currentValue,
          unit: _unit.text,
          targetPeriod: _targetPeriod,
          planTitles: _planTitles,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save goal: $e')));
      }
    }
  }
```

This is unchanged from the pre-existing file (the only edit versus what's already there is `category: _category!` replacing `category: _category`, since `_category` is now nullable per Task 7). Map the existing `_title`/`_description` fields from `_declarationController`'s text where the wizard doesn't collect them separately (e.g. `_title.text = _declarationController.text.trim();` set once before calling `_save()`, since the wizard's "declaration" is functionally the quest's title/description in the underlying data model — there is no separate title field in the wizard UI, matching A12's own wizard, which composes one declaration rather than asking for a title and a description separately).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/abundance/goal_form_screen_test.dart`
Expected: PASS (4 tests total, including Task 7's two).

- [ ] **Step 5: Run the full abundance widget suite**

Run: `flutter test test/widget/abundance/ test/unit/abundance/`
Expected: no regressions elsewhere.

- [ ] **Step 6: Stage the change**

```bash
git add lib/src/features/abundance/screens/mentee/goal_form_screen.dart test/widget/abundance/goal_form_screen_test.dart
```

---

## Task 9: Quest detail screen restyle

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goal_detail_screen.dart` — existing classes to restyle in place: `_TopHeader`, `_GoalScoreCard`, `_ActionPlansCard`, `_CommentsCard`, `_ProgressHistoryCard`, `_AttachmentsCard`, `_Badge`, `_ScoreCircle`, `_StatusDropdown`
- Test: `test/widget/abundance/goal_detail_screen_test.dart` (fixes the spec's known-failing case: missing "log period target" button)

**Interfaces:**
- Consumes: `AbundanceColors` (Task 3), `abundanceRankMedalAsset`/`abundanceQuestSceneAsset` (Task 4), `GoalFormScreen` (Tasks 7-8, for the existing Edit navigation — already wired, do not change that call).
- Produces: nothing new for later tasks; Task 10 links to this screen using its existing constructor (`GoalDetailScreen({required goalId, required service, required uid})`), unchanged by this task.

This is a restyle, not a rewrite — the existing class breakdown already matches A12's section layout (`_TopHeader` ≈ badge row + status/edit/delete; `_GoalScoreCard` ≈ Quest Score ring; `_ActionPlansCard` ≈ Weekly Targets; `_CommentsCard`, `_ProgressHistoryCard`, `_AttachmentsCard` match their A12 counterparts by name already). Read `A12-Tracker/src/app/(app)/goals/[id]/page.tsx` and `goal-controls.tsx` directly for exact copy/ordering while making these edits.

- [ ] **Step 1: Write the failing test for the missing log-period-target button**

```dart
  testWidgets('measure card shows the log-period-target action for a MERIT quest with a period',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'c1'});
    final goalId = await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
      targetPeriod: TargetPeriod.weekly,
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalDetailScreen(goalId: goalId, service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Log period target'), findsOneWidget);
  });
```

(Add this to the existing `test/widget/abundance/goal_detail_screen_test.dart` file, inside its existing `main()`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/goal_detail_screen_test.dart`
Expected: FAIL — no "Log period target" text currently rendered (per the spec's known-failing list).

- [ ] **Step 3: Add the missing button and apply the visual/copy pass**

In `_GoalScoreCard`, add a "Log period target" action button next to the existing "go the extra mile" action, calling whatever existing `onSave`/period-logging callback this class already has wired to `GoalsService`'s merit-logging methods (`logMeritTarget`/`goExtraMile` per the service — check the existing `onExtraMile` callback wiring in this class for the exact pattern to mirror for the new button).

Then apply, across all the listed classes: `AbundanceColors.background`/`surfaceRaised` for scaffold/card backgrounds, `AbundanceColors.categoryColor(goal.category.code)` for the category badge, `AbundanceColors.scoreColorFor(goal.progress)` for the score badge, `abundanceRankMedalAsset(rankForPercent(goal.progress).key)` as an `Image.asset` in `_TopHeader` next to the existing text-only rank badge, and the terminology table from the design spec (Goal → Quest, "Overall Score" → "Life Power" wherever it appears in this file, "Save goal"/"Create goal" labels already fixed by Task 7/8's rewrite of the screen it navigates to).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/abundance/goal_detail_screen_test.dart`
Expected: PASS (all tests, including the previously-known-failing ones).

- [ ] **Step 5: Stage the change**

```bash
git add lib/src/features/abundance/screens/mentee/goal_detail_screen.dart test/widget/abundance/goal_detail_screen_test.dart
```

---

## Task 10: Mentee Quests hub restyle

**Files:**
- Modify: `lib/src/features/abundance/screens/mentee/goals_hub_screen.dart` — existing classes: `_GoalsHeader`, `_GoalsSummaryGrid`, `_ScorePanel`, `_MetricCard`, `_CategoryChipsRow`, `_FilterChip`, `_GoalCard`, `_Badge`, `_EmptyGoalsState`
- Test: `test/widget/abundance/goals_hub_screen_test.dart` (fixes the spec's two known-failing cases: title `.toUpperCase()`, and `_resolveAccess` using the `loadForUser` singleton)

**Interfaces:**
- Consumes: `AbundanceColors` (Task 3), asset helpers (Task 4), `GoalDetailScreen` (Task 9) and `GoalFormScreen` (Tasks 7-8) — both already wired via existing navigation calls in this file (lines ~71-90), unchanged by this task.
- Produces: nothing new for later tasks; Task 12 (shell) embeds this screen's existing constructor unchanged.

- [ ] **Step 1: Write the failing tests for the two known bugs**

```dart
  testWidgets('quest title is not forced to uppercase', (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({'companyId': 'c1'});
    await service.createGoal(
      uid: 'u1',
      category: GoalCategory.personal,
      title: 'Run 100 km',
      targetDate: DateTime(2026, 9, 1),
      targetValue: 100,
      currentValue: 40,
      unit: 'km',
    );

    await tester.pumpWidget(MaterialApp(
      home: GoalsHubScreen(
        service: service,
        uid: 'u1',
        accessResolver: (_) async => true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Run 100 km'), findsOneWidget);
    expect(find.text('RUN 100 KM'), findsNothing);
  });

  testWidgets('access resolution does not depend on the loadForUser singleton',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final service = GoalsService(firestore);
    await firestore.collection('users').doc('u1').set({
      'companyId': 'c1',
      'activeCompanyCode': 'ABU15DN',
      'activeCompanyName': 'Abundance',
    });

    // No accessResolver override here — this must resolve access from the
    // GoalsService/user data passed in, not from a CompanyMembershipService
    // singleton that isn't configured in this test.
    await tester.pumpWidget(MaterialApp(
      home: GoalsHubScreen(service: service, uid: 'u1'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Quests'), findsWidgets);
  });
```

(Add both to the existing `test/widget/abundance/goals_hub_screen_test.dart`, inside its existing `main()`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: FAIL — both new cases fail as described in the spec.

- [ ] **Step 3: Fix the two bugs and apply the visual/copy pass**

Find the `.toUpperCase()` call applied to the quest title text (in `_GoalCard`) and remove it — display `goal.title` as stored.

Find `_resolveAccess` (or equivalently-named access-check method in `_GoalsHubScreenState`) and change it from calling `CompanyMembershipService.loadForUser` (a singleton) to instead deriving access from `GoalsService`'s already-available user/company data — mirror the `fromUserData`-style approach the spec's memory notes call out as the fix (construct the membership check from data already fetched via `service`/`uid`, not a separately-initialized singleton).

Then apply the visual/copy pass: rename "Goals hub" → "Quests" and "Overall Score"/"Goal Total Score" → "Life Power" wherever they appear in `_GoalsHeader`/`_ScorePanel`; use `AbundanceColors` throughout for backgrounds, category colors, and score colors; add `abundanceRankMedalAsset(...)` images to `_GoalCard`; add the "X / Y Missions" action-plan count and "N days left" countdown to `_GoalCard` if not already present (check the existing card fields first — `taskCount`/`completedTasks`/`daysUntilDue`-equivalent fields should already exist on whatever goal-summary type this card consumes, per the spec's confirmed screenshot details).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/abundance/goals_hub_screen_test.dart`
Expected: PASS (all tests, including the two previously-known-failing ones).

- [ ] **Step 5: Run the full abundance suite**

Run: `flutter test test/widget/abundance/ test/unit/abundance/`
Expected: all green.

- [ ] **Step 6: Stage the change**

```bash
git add lib/src/features/abundance/screens/mentee/goals_hub_screen.dart test/widget/abundance/goals_hub_screen_test.dart
```

---

## Task 11: Coach Quests roster screen

**Files:**
- Create: `lib/src/features/abundance/screens/coach/coach_quests_roster_screen.dart`
- Test: `test/widget/abundance/coach_quests_roster_screen_test.dart`

**Interfaces:**
- Consumes: `GoalsService.fetchCoachGoalsRoster()` (Task 6), `AbundanceColors` (Task 3), `GoalDetailScreen` (Task 9, for the read-only "open a quest" link).
- Produces: `CoachQuestsRosterScreen({required GoalsService service, required String coachUid})` — consumed by Task 12 (shell) for the coach's Quests tab.

Mirrors `A12-Tracker/src/app/(app)/coach/goals/page.tsx` — read it directly for exact filter labels and grouping presentation while building this.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/screens/coach/coach_quests_roster_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';

class _FakeGoalsService extends GoalsService {
  _FakeGoalsService(this._roster) : super(null);
  final List<CoachMenteeGoals> _roster;

  @override
  Future<List<CoachMenteeGoals>> fetchCoachGoalsRoster() async => _roster;
}

void main() {
  testWidgets('roster groups quests by mentee, with an empty state for coaches with none',
      (tester) async {
    final service = _FakeGoalsService(const [
      CoachMenteeGoals(menteeId: '1', menteeName: 'Maychell Alcorin', goals: []),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Maychell Alcorin'), findsOneWidget);
  });

  testWidgets('shows an empty state when the coach has no mentees', (tester) async {
    final service = _FakeGoalsService(const []);

    await tester.pumpWidget(MaterialApp(
      home: CoachQuestsRosterScreen(service: service, coachUid: 'coach1'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('No students yet'), findsOneWidget);
  });
}
```

(This requires `fetchCoachGoalsRoster` to be an overridable instance method on `GoalsService` — confirm in Task 6 it isn't accidentally marked `final` or `static`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/coach_quests_roster_screen_test.dart`
Expected: FAIL — the screen doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';

import 'package:selfcare_projects/src/features/abundance/screens/mentee/goal_detail_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';

/// Read-only: every mentee this coach is assigned, with their quests,
/// mirroring `A12-Tracker`'s `coach/goals` page. Rows link out to
/// [GoalDetailScreen]; nothing here writes.
class CoachQuestsRosterScreen extends StatefulWidget {
  const CoachQuestsRosterScreen({
    super.key,
    required this.service,
    required this.coachUid,
  });

  final GoalsService service;
  final String coachUid;

  @override
  State<CoachQuestsRosterScreen> createState() =>
      _CoachQuestsRosterScreenState();
}

class _CoachQuestsRosterScreenState extends State<CoachQuestsRosterScreen> {
  late Future<List<CoachMenteeGoals>> _rosterFuture;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _rosterFuture = widget.service.fetchCoachGoalsRoster();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbundanceColors.background,
      body: FutureBuilder<List<CoachMenteeGoals>>(
        future: _rosterFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final roster = snapshot.data!
              .where((entry) => entry.menteeName
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()))
              .toList();

          if (roster.isEmpty) {
            return Center(
              child: Text(
                'No students yet',
                style: TextStyle(color: AbundanceColors.foreground),
              ),
            );
          }

          return ListView.builder(
            itemCount: roster.length,
            itemBuilder: (context, index) {
              final entry = roster[index];
              return _MenteeQuestsGroup(
                entry: entry,
                onOpenGoal: (goalId) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GoalDetailScreen(
                      goalId: goalId,
                      service: widget.service,
                      uid: entry.menteeId,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MenteeQuestsGroup extends StatelessWidget {
  const _MenteeQuestsGroup({required this.entry, required this.onOpenGoal});

  final CoachMenteeGoals entry;
  final ValueChanged<String> onOpenGoal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            entry.menteeName,
            style: TextStyle(
              color: AbundanceColors.foreground,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        for (final goal in entry.goals)
          ListTile(
            onTap: () => onOpenGoal(goal.id),
            title: Text(goal.title,
                style: TextStyle(color: AbundanceColors.foreground)),
            subtitle: Text(
              '${goal.category.label} · ${goal.progress}%',
              style: TextStyle(color: AbundanceColors.muted),
            ),
          ),
      ],
    );
  }
}
```

(`goal.category.label` assumes `GoalCategory` already exposes a display label field per its `domain.dart` definition — confirm the exact field name there before use; if it differs, use that name instead.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/abundance/coach_quests_roster_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Stage the change**

```bash
git add lib/src/features/abundance/screens/coach/coach_quests_roster_screen.dart test/widget/abundance/coach_quests_roster_screen_test.dart
```

---

## Task 12: AbundanceShellScreen

**Files:**
- Create: `lib/src/features/abundance/screens/abundance_shell_screen.dart`
- Test: `test/widget/abundance/abundance_shell_screen_test.dart`

**Interfaces:**
- Consumes: `AbundanceColors` (Task 3), `GoalsHubScreen` (Task 10, mentee Quests tab), `CoachQuestsRosterScreen` (Task 11, coach Quests tab), existing `AbundanceMenteeDashboardScreen` (Home placeholder), existing `CoachDashboardScreen` (coach Home placeholder), existing `Leaderboard` (Guild placeholder), existing `ProfileSettings` (Profile placeholder), existing `BottomSheetWidget.show(context)` (More).
- Produces: `AbundanceShellScreen({required bool isCoach, required GoalsService service, required String uid, required CompanyThemeData companyTheme})` — consumed by Task 13.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/abundance/screens/abundance_shell_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

void main() {
  testWidgets('shows the Quests tab body by default and switches tabs on tap',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: AbundanceShellScreen(
        isCoach: false,
        service: service,
        uid: 'u1',
        companyTheme: CompanyThemeData.standard.copyWith(
          companyCode: 'ABU15DN',
          companyName: 'Abundance',
          isCompanyTheme: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('ABUNDANCE 12'), findsOneWidget);
    expect(find.text('THE GAME OF MY LIFE'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets); // the tab label itself, still visible

    await tester.tap(find.text('Quests'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Life Power'), findsWidgets);
  });

  testWidgets('coach shell shows the coach roster on the Quests tab',
      (tester) async {
    final service = GoalsService(FakeFirebaseFirestore());

    await tester.pumpWidget(MaterialApp(
      home: AbundanceShellScreen(
        isCoach: true,
        service: service,
        uid: 'coach1',
        companyTheme: CompanyThemeData.standard.copyWith(
          companyCode: 'ABU15DN',
          companyName: 'Abundance',
          isCompanyTheme: true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quests'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No students yet'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/abundance/abundance_shell_screen_test.dart`
Expected: FAIL — file doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';

import 'package:selfcare_projects/src/features/abundance/screens/coach/coach_quests_roster_screen.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/abundance_mentee_dashboard_screen.dart';
import 'package:selfcare_projects/src/features/abundance/screens/mentee/goals_hub_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
import 'package:selfcare_projects/src/features/abundance/theme/abundance_theme.dart';
import 'package:selfcare_projects/src/features/authentication/screen/coach_dashboard/coach_dashboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/leaderboard/leaderboard_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/profile/profile_settings.dart';
import 'package:selfcare_projects/src/models/bottom_sheet.dart';
import 'package:selfcare_projects/src/services/company_theme_service.dart';

/// The custom app shell (header + 5-tab bottom nav) A12-Tracker wraps every
/// screen in, built only for Abundance members. Only the Quests tab has a
/// finished redesign so far (mentee: [GoalsHubScreen]; coach:
/// [CoachQuestsRosterScreen]) — Home/Guild/Profile/More render InnerU's
/// existing equivalent screens verbatim as placeholders until their own
/// specs land (see the design spec's "App shell" section).
class AbundanceShellScreen extends StatefulWidget {
  const AbundanceShellScreen({
    super.key,
    required this.isCoach,
    required this.service,
    required this.uid,
    required this.companyTheme,
  });

  final bool isCoach;
  final GoalsService service;
  final String uid;
  final CompanyThemeData companyTheme;

  @override
  State<AbundanceShellScreen> createState() => _AbundanceShellScreenState();
}

class _AbundanceShellScreenState extends State<AbundanceShellScreen> {
  int _index = 0; // 0=Home, 1=Quests, 2=Guild, 3=Profile, 4=More
  static const _tabLabels = ['Home', 'Quests', 'Guild', 'Profile', 'More'];
  static const _tabIcons = [
    Icons.home_outlined,
    Icons.military_tech_outlined,
    Icons.groups_outlined,
    Icons.person_outline,
    Icons.more_horiz,
  ];

  Widget get _questsTabBody => widget.isCoach
      ? CoachQuestsRosterScreen(service: widget.service, coachUid: widget.uid)
      : GoalsHubScreen(service: widget.service, uid: widget.uid);

  Widget get _homeTabBody => widget.isCoach
      ? const CoachDashboardScreen()
      : AbundanceMenteeDashboardScreen(
          initialCompanyTheme: widget.companyTheme,
          service: widget.service,
        );

  List<Widget> get _tabBodies => [
        _homeTabBody,
        _questsTabBody,
        const Leaderboard(),
        const ProfileSettings(),
        const SizedBox.shrink(), // "More" never actually renders — see onTap below.
      ];

  void _onTabTapped(int newIndex) {
    if (newIndex == 4) {
      BottomSheetWidget.show(context);
      return; // stay on the current tab; More is a trigger, not a screen.
    }
    setState(() => _index = newIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AbundanceColors.background,
      appBar: AppBar(
        backgroundColor: AbundanceColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ABUNDANCE 12',
                style: TextStyle(
                    color: AbundanceColors.foreground,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            Text('THE GAME OF MY LIFE',
                style: TextStyle(
                    color: AbundanceColors.primaryGold, fontSize: 10)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_none, color: AbundanceColors.foreground),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(index: _index, children: _tabBodies),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AbundanceColors.surfaceRaised,
        selectedItemColor: AbundanceColors.primaryGold,
        unselectedItemColor: AbundanceColors.muted,
        currentIndex: _index,
        onTap: _onTabTapped,
        items: [
          for (var i = 0; i < _tabLabels.length; i++)
            BottomNavigationBarItem(
              icon: Icon(_tabIcons[i]),
              label: _tabLabels[i],
            ),
        ],
      ),
    );
  }
}
```

(`AbundanceMenteeDashboardScreen({initialCompanyTheme, service})` and `GoalsHubScreen({service, uid, accessResolver})` constructors confirmed directly against the current file contents — all parameters above are real and optional/nullable, so this compiles against the existing screens unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/abundance/abundance_shell_screen_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Add the non-matching-company guard test**

```dart
  testWidgets('AbundanceShellScreen is never constructed for a non-Abundance company',
      (tester) async {
    // This is a documentation test: AbundanceShellScreen has no internal
    // gating of its own — Task 13's integration point is what decides
    // whether to build it at all. See abundance_company_test.dart (Task 1)
    // for the actual gating-logic coverage.
  });
```

(This documents the design decision rather than testing new behavior — the real gate is Task 1's `AbundanceCompany.matches`, exercised again structurally in Task 13.)

- [ ] **Step 6: Stage the change**

```bash
git add lib/src/features/abundance/screens/abundance_shell_screen.dart test/widget/abundance/abundance_shell_screen_test.dart
```

---

## Task 13: Wire `AbundanceShellScreen` into `Setuppage`/`CoachSetuppage`

**Files:**
- Modify: `lib/setup_navbar.dart`

**Interfaces:**
- Consumes: `AbundanceCompany.matches` (Task 1), `AbundanceShellScreen` (Task 12).

`Setuppage`/`CoachSetuppage` already resolve `_companyTheme` (via `_loadCompanyTheme()` in `initState`, using `CompanyThemeService.resolveForUser`) before their `build()` runs — this is the first point in the existing widget tree where the real company code/name are available, which is why the branch goes here rather than in `AuthRoleHome` (which only has role info, not company info, synchronously).

- [ ] **Step 1: Add the import**

At the top of `lib/setup_navbar.dart`, add:

```dart
import 'package:selfcare_projects/src/features/abundance/domain/abundance_company.dart';
import 'package:selfcare_projects/src/features/abundance/screens/abundance_shell_screen.dart';
import 'package:selfcare_projects/src/features/abundance/services/goals_service.dart';
```

- [ ] **Step 2: Branch in `_SetuppageState.build()`**

Find (line ~94):

```dart
  @override
  Widget build(BuildContext context) {
    final theme = _companyTheme;
    return Theme(
```

Insert immediately before it:

```dart
  @override
  Widget build(BuildContext context) {
    final theme = _companyTheme;
    if (AbundanceCompany.matches(theme.companyCode, theme.companyName)) {
      return AbundanceShellScreen(
        isCoach: false,
        service: GoalsService(),
        uid: AuthService.instance.currentUserId ?? '',
        companyTheme: theme,
      );
    }
    return Theme(
```

(The existing `return Theme(...)` block and its closing stays exactly as-is below this — only the new `if` block is inserted above it.)

- [ ] **Step 3: Branch in `_CoachSetuppageState.build()`**

Same change in the coach state class (line ~217), with `isCoach: true`:

```dart
  @override
  Widget build(BuildContext context) {
    final theme = _companyTheme;
    if (AbundanceCompany.matches(theme.companyCode, theme.companyName)) {
      return AbundanceShellScreen(
        isCoach: true,
        service: GoalsService(),
        uid: AuthService.instance.currentUserId ?? '',
        companyTheme: theme,
      );
    }
    return Theme(
```

- [ ] **Step 4: Manual verification (no automated test for this step — it wires two already-tested widgets together)**

Run: `flutter analyze lib/setup_navbar.dart`
Expected: no new errors.

Then run the full existing test suite to confirm the branch doesn't break any non-Abundance-company test fixture (none of the existing tests construct a `CompanyThemeData` with `companyCode: 'ABU15DN'` or `companyName: 'Abundance'`, so this branch should never trigger in current tests):

Run: `flutter test`
Expected: same pass/fail counts as the end of Task 10 plus all of Tasks 1-12's new tests, no new failures.

- [ ] **Step 5: Stage the change**

```bash
git add lib/setup_navbar.dart
```

---

## Task 14: Full verification pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full Flutter test suite**

Run: `flutter test`
Expected: all tests pass, including every test added in Tasks 1, 3, 4, 6, 7, 8, 9, 10, 11, 12, and the untouched pre-existing suite.

- [ ] **Step 2: Run the full backend suite**

Run: `cd backend && vendor/bin/phpunit`
Expected: all tests pass, including Task 5's two new tests.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`
Expected: no new warnings/errors introduced by this plan's changes (pre-existing warnings elsewhere in the repo are out of scope).

- [ ] **Step 4: Manual smoke-test checklist against the screenshots**

Using a test account whose company has code `ABU15DN` or name `ABUNDANCE`:
- [ ] App opens directly into the custom shell (header + 5-tab bottom nav), not the standard InnerU shell.
- [ ] Quests tab (mentee): Life Power ring, category chips, quest cards with rank medal images, "X / Y Missions", "N days left" all render.
- [ ] Tapping a quest card opens the restyled detail screen with the "Log period target" button visible for a MERIT quest.
- [ ] Tapping "New Quest" opens the 4-step wizard; completing it creates a quest and returns to the hub.
- [ ] Quests tab (coach account): shows the roster grouped by mentee instead.
- [ ] Home/Guild/Profile tabs show the existing InnerU screens (unchanged) inside the new shell chrome.
- [ ] Tapping "More" opens the existing hamburger bottom sheet.
- [ ] A non-Abundance test account sees no change at all — standard shell, standard "Goals" tab wording, no Quests/Life Power terminology anywhere.

- [ ] **Step 5: Report results to the user**

Summarize pass/fail counts and any manual-checklist items that didn't match, rather than silently proceeding if something is off.
