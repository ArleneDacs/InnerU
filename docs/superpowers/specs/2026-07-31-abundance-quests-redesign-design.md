# Abundance Quests Redesign — Design

**Date:** 2026-07-31
**Status:** Approved by user

## What this is

Rebuild InnerU's existing Abundance-exclusive "Goals" feature
(`lib/src/features/abundance/`) so it matches its reference implementation —
`A12-Tracker` (a Next.js/Prisma/Postgres app, now vendored into this repo at
`/A12-Tracker`) — as closely as a native Flutter screen can: exact colors,
layout, product terminology, button behavior, and the actual image assets A12
ships, not just its color palette. This includes the custom app shell (header
+ bottom nav) that wraps every A12 screen, confirmed against live screenshots
of the running web app, not just its source.

A12-Tracker is, in full, a much larger product than Goals/Quests alone — its
screenshots also cover a Home dashboard, a Guild/leaderboard, a full Profile
("Character Sheet"), a coach Students roster, admin Core Tasks settings,
Achievements, and Notifications. All of that is confirmed in scope
eventually, matching the original 5-phase plan, but is sequenced as separate
follow-on specs (each brainstormed and approved the same way this one was)
rather than folded into this one. This spec's functional scope stays Quests
only; see "App shell" below for how the other, not-yet-built areas are
handled in the meantime.

This supersedes one call from the original
[2026-07-17 port design](2026-07-17-a12-tracker-port-design.md): that spec
explicitly put "A12's web UI, Tailwind styling, and React components" out of
scope, in favor of screens that "follow InnerU's existing look." A partial
exception was already carved out on 2026-07-18 (a dark navy+gold reskin of
just the Goals Hub, after a light-theme attempt was explicitly rejected). This
spec extends that exception across the whole Goals/Quests feature and
formalizes an exact-match mandate going forward for it.

Only Phase 1 of the original 5-phase plan has shipped (Goals, mentee-only).
Phases 2–5 (disciplines/check-ins, scores/leaderboards, the rest of the coach
layer, achievements/notifications/admin) do not exist yet and are unaffected
by this spec.

## Scope condition

This redesign — and everything it touches — applies **only** to members of
the Abundance company, matched by:

```
code.trim().toUpperCase() == 'ABU15DN' || name.trim().toUpperCase() == 'ABUNDANCE'
```

All other companies must see exactly what they see today: the plain to-do
list, with no Quests concept at all (this feature is already Abundance-only —
see "Existing gating bug" below).

## Existing gating bug (fixed here)

Two independent, drifting heuristics currently decide "is this Abundance":

- `todo_list.dart`'s `_isAbundance12Company()`
- `company_theme_service.dart`'s `_matchesAbundance12()`

Both require the company's name or code to contain `"12"` (matching things
like `A12`, `ABUND12`, `AB12*`). Neither matches a company whose real code is
`ABU15DN` and name is exactly `ABUNDANCE` — no `"12"` anywhere in either
string. In effect, the real production Abundance company likely never
triggers the existing dark-theme restyle or the Goals Hub swap today.

**Fix:** introduce one shared helper —
`AbundanceCompany.matches(code, name)` — implementing the exact condition
above, and point both existing call sites at it, deleting their private
heuristics. One source of truth instead of two.

## App shell

Every A12 screenshot shows the same wrapper: a top header ("ABUNDANCE 12" /
"THE GAME OF MY LIFE" wordmark, notification bell, avatar) and a 5-tab bottom
nav (Home, Quests, Guild, Profile, More). This wraps the Quests screens too,
so it's built now rather than deferred — a new `AbundanceShellScreen` (or
similar), gated by the same `AbundanceCompany.matches()` check, that replaces
InnerU's standard header/bottom-nav for Abundance members only. Other
companies' navigation chrome is untouched — this is a new, parallel shell,
not a modification of the shared one.

Only the **Quests** tab has an approved design (this spec). The other four
tabs need to render *something*, so until their own specs land:

- **Home** → InnerU's existing `abundance_mentee_dashboard_screen.dart`
  (already built, already Abundance-specific).
- **Guild** → InnerU's existing `leaderboard_screen.dart` (the current
  userpoints leaderboard).
- **Profile** → InnerU's existing `profile_settings.dart`.
- **More** → InnerU's existing overflow/more menu, whatever that currently
  is for these users.

None of these four are restyled or renamed as part of this spec — they are
placeholders inside the new shell, carried over as-is, and each becomes its
own brainstorm-and-spec cycle later (Home dashboard, Guild/leaderboard,
Profile/Character Sheet, Students roster, Core Tasks admin, Achievements,
Notifications all confirmed in scope eventually, per the screenshots, just
not now).

## Screens in scope

All under `lib/src/features/abundance/`, rebuilt in place (existing files are
1,500–1,700 lines each and were built to the old "native look" mandate, so
this is closer to a rewrite than a restyle for goal_form_screen.dart and
goal_detail_screen.dart):

1. **Mentee Quests hub** (`goals_hub_screen.dart`) — mirrors
   `A12-Tracker/src/app/(app)/goals/page.tsx`: a Life Power ring card, a
   horizontally-scrolling category chip row (collapsing to icon-only below
   phone width, matching A12's own `sm` breakpoint behavior), and a list of
   quest cards (single-column — A12's own mobile layout is already
   single-column, so that's the direct fidelity target, not its desktop
   grid). Confirmed from screenshots: each card shows a category badge, a
   status badge ("In progress"), a score-percentage badge, a rank-medal
   badge (image + name, e.g. "LEGEND"), the quest title, a progress bar, a
   "X / Y Missions" action-plan count, and a "N days left" countdown.
2. **Quest detail** (`goal_detail_screen.dart`) — mirrors
   `goals/[id]/page.tsx` + `goal-controls.tsx`. Confirmed structure, top to
   bottom: title; badge row (category, status, score %, rank, MERIT/
   MILESTONE type); status dropdown + Edit + Delete row; a "Quest Score"
   ring with an explanatory line; started/target dates; the quest's
   declaration text plus its chosen "qualities" (e.g. Commitment,
   Discipline); a "Weekly Targets" list — each action plan tagged
   Done/In progress/Not started, with a date range, reorder (up/down) and
   remove controls, plus an "Add an action plan…" input; a Comments section
   (coach-only checkbox, "Post comment"); a Progress History timeline
   (percentage-change entries with actor + relative timestamp); an
   Attachments section (empty state: "Nothing attached").
3. **Quest creation/edit** (`goal_form_screen.dart`) — mirrors
   `goals/goal-wizard.tsx`. A12 uses a full multi-step wizard here (1,671
   lines); InnerU currently has a single-page form. Matching "exactly" means
   restructuring this into a step wizard, not reskinning the existing form.
   Confirmed 4 steps from screenshots: **1. What** (optional "Get 5 AI
   suggestions" entry point, then a declaration textarea — "What do you
   joyfully see yourself achieving?"); **2. How** (category picker, Gain/
   Release direction toggle, a measure dropdown, target value, target
   period, and an optional action-plan list builder); **3. When & qualities**
   (deadline date, defaulting to the council deadline; a qualities chip
   picker plus freeform comma-separated text); **4. Declaration** (read-only
   review of the composed declaration + chosen qualities, Back/Submit). The
   "Get 5 AI suggestions" entry point is UI-visible in the screenshots but
   its backing behavior isn't confirmed from source yet — flagged for the
   implementation plan to investigate (`A12-Tracker`'s actions/AI-suggestion
   code) rather than guessed at here.
4. **Coach Quests roster** (new screen, coach dashboard) — mirrors
   `coach/goals/page.tsx`: every mentee's quests on one page, grouped by
   mentee, with search + category/status/score filters, read-only, linking
   out to quest detail. Nothing like this exists in InnerU today. (This is
   distinct from the "Students" roster seen in the screenshots, which is a
   general — not quest-filtered — coach landing page; that one is out of
   scope here, folded into a later Students/coach-dashboard spec.)

**Out of scope** (unaffected by this spec, confirmed for later work under the
original 5-phase plan, each its own future spec): the Home dashboard's
"Today's Mission"/core-tasks card, the Guild leaderboard, the Profile
"Character Sheet" (including its theme picker and edit-profile form), the
Students general roster, admin's Core Tasks settings and
`goal-settings-form.tsx`, Achievements, Notifications, and the other RPG
components that live outside Goals (hero banner, hall-of-heroes, mentor-card,
relic-card, reward-panel, earned-badges).

## Terminology

Ported verbatim from A12's actual source (not reinvented), for Abundance
members only — every other company keeps seeing "Goals"/"Overall Score":

| InnerU today | A12 (this redesign) |
|---|---|
| Goal | Quest |
| Goals hub | Quests |
| Overall / Goal Total Score | Life Power |
| Rank ladder | Herald → Guardian → Crusader → Archon → Legend → Ancient → Divine → Immortal → Master Immortal → Titan (already correctly implemented in `domain.dart`'s `rankForPercent`, no change needed there) |

## Visual tokens

New `abundance_theme.dart` (single source of truth — no more per-screen magic
hex), values taken directly from `A12-Tracker/src/app/globals.css`'s `.dark`
block (A12's own comment: "Dark is the real theme... Light is a warm
parchment counterpart" — dark is what we port, consistent with the earlier
rejected-light-theme decision):

- Background `#080c1c`, surface raised `#0d1330`, surface sunken `#060916`
- Border `#1c2650`, foreground `#f2ecd8`, muted `#9fa8c9`
- Primary (gold) `#eab73f`, accent (cyan) `#58c8ff`
- Category colors: Personal `#5ee6a8` (green), Professional `#a98bff`
  (purple), Contribution `#58c8ff` (cyan)
- Score colors: excellent `#5ee6a8`, good `#58c8ff`, warning `#eab73f`,
  critical `#f0607a`

## Image assets

Copied from `A12-Tracker/public/{ranks,scenes}/` into a new
`assets/images/abundance/` folder, added as its own explicit entry in
`pubspec.yaml` (Flutter doesn't include subdirectories automatically —
`assets/images/login-image/` already gets its own line for the same reason).
Referenced through a Dart constants map mirroring A12's own `RANK_SRC`/
`SCENES` maps.

- **Rank medal images** (5 PNGs, used on quest cards): A12 collapses its 10
  rank keys onto 5 actual images — `archon.png` covers Herald/Guardian/
  Crusader/Archon, `legend.png`, `ancient.png`, `divine.png`, and
  `immortal.png` covers Immortal/Master Immortal/Titan. Port this exact
  many-to-one mapping.
- **Category scene art** (3 WebPs): `quest-personal.webp`,
  `quest-professional.webp`, `quest-contribution.webp` — category-tinted
  background art. Flutter decodes WebP natively on iOS/Android; no
  conversion needed.
- **Page backdrop** (`hero-dark.webp`, 1920×1080): in A12 this sits behind
  the *entire authenticated shell*. Applying it there would mean touching
  shell/nav chrome shared by every company, which conflicts with keeping this
  change isolated. Instead it's applied only as background art within the
  Quests screens themselves.

Not ported: the 13 achievement badge PNGs (`ranks/achievements/` — belong to
the not-yet-built Achievements feature) and `brand/` logo/hero-video assets
(marketing/sign-in pages, not Goals-specific).

## Data layer

`goals_service.dart` already talks to the Laravel/Postgres API (migrated
off Firestore already; the `cloud_firestore` import it still carries appears
unused for this feature) and needs little to no change for the mentee
screens.

The coach roster needs one new backend endpoint — e.g.
`GET /coach/goals` — returning all of a coach's mentees' quests in one
grouped response, rather than the Flutter client looping the existing
per-mentee `GET /coach/mentees/{menteeId}/goals` endpoint once per mentee.
Mirrors `A12-Tracker`'s `listMenteeGoals(coach, filter)` /
`listCoachNavGroups()` server functions, scoped through InnerU's existing
`coach_mentees`/group tables.

## Testing

- Existing known-failing widget tests get fixed as part of this rewrite
  since it touches these exact screens anyway:
  `test/widget/abundance/goals_hub_screen_test.dart` (title
  `.toUpperCase()`, `_resolveAccess` using the `loadForUser` singleton),
  `test/widget/abundance/goal_detail_screen_test.dart` (missing
  "log period target" button), `test/widget/abundance/goal_form_screen_test.dart`
  ("Save goal" vs "Create goal" label).
- New: a unit test for `AbundanceCompany.matches()` (exact-match and
  near-miss cases, e.g. codes containing but not equal to `ABU15DN`), a new
  widget test for the coach roster screen, wizard step-navigation tests for
  the rebuilt quest creation flow, and a widget test for
  `AbundanceShellScreen` confirming it renders for a matching company, stays
  out of the way for every other company, and that its four placeholder tabs
  resolve to the existing screens named above.
- No Firestore involved in any of this — existing Laravel/PHPUnit patterns
  apply for the new backend endpoint (`vendor/bin/phpunit`, not
  `php artisan test --configuration=`, which is broken per prior findings).

## Security & isolation

- The `AbundanceCompany.matches()` gate is the only new conditional; it
  replaces two existing ones rather than adding a third. No other company's
  code path changes.
- The new coach roster endpoint enforces the same coach-sees-own-mentees
  authorization as the existing per-mentee endpoint — it is a grouped read,
  not a new access model.
- New screens, the new shell, and assets live entirely under
  `lib/src/features/abundance/` and `assets/images/abundance/`. The new
  `AbundanceShellScreen` is an addition, not a modification — InnerU's
  existing header/bottom-nav widgets are untouched and still used verbatim
  by every other company (and reused, unmodified, as this shell's own
  Home/Guild/Profile/More tab content, per "App shell" above).
