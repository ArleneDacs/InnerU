# A12-Tracker → InnerU Port — Design

**Date:** 2026-07-17
**Status:** Approved by user (sections 1–3 approved in brainstorming session)

## What this is

Rebuild the full feature set of A12-Tracker ("Abundance Hub" — a Next.js +
Prisma/Postgres coaching & accountability web app at `~/A12-Tracker`) natively
inside InnerU (Flutter + Firebase). There is no copy-paste path between the
stacks; this is a reimplementation that ports A12's domain logic and product
rules into Dart and Firestore.

Reference material in the source repo: `docs/ARCHITECTURE.md` (scoring formula,
RBAC rules, conventions), `prisma/schema.prisma` (31 models),
`src/lib/scoring.ts` and `src/lib/domain.ts` (the logic to port).

## Decisions already made (user-approved)

1. **Scope:** everything — all A12 subsystems, delivered in five phases.
2. **Role placement:** admin features go in InnerU's admin dashboard, coach
   features in the coach dashboard, mentee features in the user area.
   A12 "mentee" = InnerU role `user`.
3. **Overlaps:** keep both side by side. InnerU's existing userpoints
   leaderboard stays; the A12 score leaderboard is added alongside it.
   Users' personal notes stay; coaching notes are a separate coach feature.
4. **Architecture:** pure Firestore rebuild (option A). No Cloud Functions, no
   billing change, no external backend. Scores computed live on read in the
   app; history snapshots written opportunistically.

## Code layout

New feature area: `lib/src/features/abundance/`

```
abundance/
  domain/     pure Dart — no Firestore imports
              scoring.dart, streaks.dart, day_key.dart, statuses.dart,
              achievement_defs.dart, goal_categories.dart
  services/   Firestore access, one per feature; visibility rules enforced here
              goals_service.dart, core_tasks_service.dart, checkins_service.dart,
              scores_service.dart, coaching_notes_service.dart, groups_service.dart,
              notifications_service.dart, maintenance_service.dart, ...
  screens/
    mentee/   goals hub, goal detail/form, daily disciplines, check-in,
              my score, score leaderboard, achievements, notifications
    coach/    roster, mentee detail, review queue, coaching notes,
              groups & delegations, coach leaderboard
    admin/    core tasks CRUD, groups admin, analytics, activity log,
              recalculate
```

Dependency rule (same as A12): `screens → services → domain`. Screens never
touch Firestore directly; `domain/` imports nothing from the other layers.

Unlike InnerU's existing singleton-bound services, every new service takes
`FirebaseFirestore` as a constructor parameter so it is testable with
`fake_cloud_firestore`.

## Data model (Firestore)

All new collections carry a `companyId` field; every query scopes by it.
InnerU's existing `companies` collection plays A12's "organization" role.

| A12 model(s) | Firestore | Notes |
|---|---|---|
| Organization | `companies` (existing) | reused as-is |
| User, Role, UserRole | `users` (existing) | `role` field + `isCoach` flag; multi-role users (coach who is also mentored) supported |
| CoachGroup, GroupMembership | `coach_groups` (existing, extended) | member list per group |
| CoachDelegation | `coach_delegations` (new) | coachId, delegateId, menteeIds, expiresAt |
| GoalCategory | Dart constants | Personal / Professional / Contribution; all three required; fixed, not admin-editable |
| Goal | `goals` | userId, companyId, category, status, title, description, targetDate, cached `progress`, optional measurable target (startValue, targetValue, currentValue, linked core task) |
| GoalTask | `goals/{id}/tasks` | title, weight (default 1), done, sortOrder |
| GoalUpdate | `goals/{id}/updates` | progress-update timeline entries |
| GoalComment | `goals/{id}/comments` | mentee + coach comments |
| MeritLog | `goals/{id}/merits` | one per goal per day; amount added to currentValue; written when a linked core task is completed or logged manually |
| CoreTask | `core_tasks` | per company; name, description, icon, points, isActive, sortOrder; admin CRUD |
| CoreTaskCompletion | `core_task_completions` | doc ID `{uid}_{taskId}_{yyyy-MM-dd}`; presence = done; un-ticking deletes the doc (no `false` tombstones) |
| DailyCheckIn | `daily_checkins` | doc ID `{uid}_{yyyy-MM-dd}`; wins, challenges, lessons, gratitude, tomorrowFocus, mood 1–5 |
| CheckInReview | `daily_checkins/{id}/reviews` | coach comments, threaded; multiple coaches may review |
| CoachingNote, NoteActionItem | `coaching_notes` | coachId, menteeId, body, action items with done flags; plain text (no HTML — A12's sanitizer is unnecessary in Flutter) |
| ScoreSnapshot (+ coach/group/org variants) | `score_snapshots` | doc ID `{scope}_{id}_{yyyy-MM-dd}`; overall + component scores; history only, never read for current values |
| LeaderboardEntry | `leaderboard_entries` | day-keyed frozen ranks so "you climbed N places" has a yesterday |
| UserStreak | computed live | derived in domain layer from completions + check-ins |
| Achievement | Dart constants | definition list ported from A12 seed |
| UserAchievement | `user_achievements` | doc ID `{uid}_{achievementKey}`; unlockedAt |
| Notification | `notifications` | deterministic doc IDs `{type}_{target}_{yyyy-MM-dd}` for dedupe |
| NotificationPreference | map on `users` doc | per-type toggles |
| ActivityLog | `activity_logs` | who did what, when; admin-visible |
| Attachment | Firebase Storage + `attachments` | metadata doc pointing at storage path |

### Conventions

- **Day keys are local dates** formatted `yyyy-MM-dd`, matching InnerU's
  existing convention (used 32+ places), NOT A12's UTC buckets.
- **Missed days are absences**: no completion doc means not done. History
  views re-expand the trailing window so gaps render as gaps.
- **A goal requires at least one task at creation** — enforced in
  `goals_service.createGoal` and by the form.
- **`goals.progress` is a cached mirror** of the task-derived score, updated
  on every task write, so lists read one field instead of the subcollection.

## Features per role

### Mentee (user area — new entries on the existing navbar/dashboard)

- **Goals hub**: three category tabs; goal cards with progress bars. Goal
  detail: task checklist (tick/untick, weighted), updates timeline, comments,
  status changes. Completed → scores 100 regardless of tasks. Abandoned →
  withdrawn from all averages (not zero). Measurable goals accrue progress via
  daily merit logs, optionally auto-fed by a linked daily discipline.
- **Daily disciplines card** on the dashboard: today's core tasks as a tick
  list with points.
- **Daily check-in**: one per day (wins, challenges, lessons, gratitude,
  tomorrow's focus, mood 1–5); history list; coach feedback threaded on past
  check-ins.
- **My Score**: overall 0–100, three component gauges, streak flame, 30-day
  trend from snapshots, and gap hints (e.g. "no Contribution goal yet" —
  A12's `missingCategories`).
- **Score leaderboard**: new tab beside the existing userpoints leaderboard.
  Scoped to the mentee's own coach group only; mentees are never shown org or
  coach boards (visibility enforced in the service, like A12's
  `visibleUserIds()`).
- **Achievements** gallery (locked/unlocked) and **notification center** with
  per-type preferences.

### Coach (coach dashboard)

- **Mentee roster**: live scores, streaks, last check-in, at-risk flags.
- **Mentee detail**: goals, check-in history, score breakdown. Coaches read
  everyone in the company; they write only to their own mentees unless a
  delegation exists (explicit, expirable). Exception carried from A12: any
  coach may write a coaching note about any mentee they can see.
- **Check-in review queue**: unreviewed check-ins across their mentees; write
  feedback comments.
- **Coaching notes** with action items — separate from users' personal notes.
- **Group & delegation management** for their own groups.
- **Coach leaderboard**: coaches ranked by average mentee overall score,
  visible org-wide.

### Admin (admin dashboard)

- **Core tasks CRUD** per company (name, icon, points, active, order).
- **Groups admin**: create groups, assign coach and members (extends the
  existing `coach_groups` screens).
- **User/role management** additions to existing viewalluser/addcoach screens,
  including multi-role users.
- **Recalculate button**: forces the maintenance sweep (snapshots +
  leaderboard freeze + notification sweep).
- **Analytics dashboard**: participation rates, score distributions, at-risk
  mentees, company trend (charts via the existing `fl_chart` dependency).
- **Activity log viewer**.

## Scoring engine (Dart port of `scoring.ts`)

```
overall = 0.5 × goals + 0.3 × disciplines + 0.2 × consistency   (each 0–100)
```

- **Goals**: per-goal score = Σ weight(done tasks) / Σ weight(all tasks) × 100,
  with the Completed/Abandoned rules above. Category score = mean of its
  goals. Goal Total = the three categories equally weighted; an empty required
  category scores zero deliberately.
- **Disciplines**: completions ÷ expected over a trailing 30 days
  (`SCORING_WINDOW_DAYS`), window clamped to the user's join date.
- **Consistency**: 60% streak (saturating at 30 days) + 40% check-in rate over
  the same window. A day counts toward the streak if the user did anything
  (one discipline tick or a check-in). The current streak may end today **or
  yesterday** — the grace that stops every streak resetting at midnight.
- **Coach score** = average of their mentees' overall scores.
- **Live on read**: nothing reads a snapshot for a current value. Leaderboard
  computation batches Firestore reads (chunked `whereIn` queries over
  completions/check-ins/goals) rather than issuing per-user queries.

## Background jobs without a server

A12's nightly cron becomes an opportunistic, idempotent maintenance sweep in
`maintenance_service.dart`:

- **Trigger**: app open (any user in the company), plus the admin Recalculate
  button.
- **Concurrency guard**: a per-company `maintenance/{companyId}` marker doc
  claimed in a Firestore transaction (`lastRunDay` check-and-set) so two
  phones don't both run the sweep.
- **Work** (all idempotent, keyed on day buckets):
  1. Backfill missing `score_snapshots` for elapsed days.
  2. Freeze `leaderboard_entries` ranks.
  3. Notification sweep — missed disciplines, goal deadlines approaching,
     check-in reminders, rank movement, new achievement unlocks — deduped by
     deterministic doc IDs.

Failure mode is benign: if nobody opens the app for a day, the next open
backfills the gap; trend charts simply interpolate.

## Security & error handling

- Firestore security rules for every new collection: company scoping,
  owner-only writes on own records, admin override. Coach read visibility and
  the delegation write rules are enforced in the service layer — finer than
  rules can express without a server; this matches how InnerU works today and
  is the accepted trade-off of the serverless choice.
- Firestore offline persistence covers discipline ticks and check-ins made
  offline; day-keyed doc IDs make replays idempotent.
- Services surface failures as typed results/exceptions; screens show
  snackbars consistent with existing InnerU patterns.

## Testing

- `test/unit/abundance/` — pure-Dart tests for scoring (all formula branches:
  weighted tasks, Completed/Abandoned, empty category, window clamping),
  streak grace, day-key math, achievement unlock predicates.
- Service tests with `fake_cloud_firestore` (new dev dependency), possible
  because new services take the Firestore instance as a parameter.
- `test/widget/abundance/` — goal form (rejects zero-task goals), daily tick
  list, check-in form.

## Phases (each ships independently, each gets its own implementation plan)

1. **Foundations + Goals** — domain library incl. full scoring engine with
   unit tests; goals hub/detail/form end-to-end for mentees.
2. **Disciplines + Check-ins** — admin core-task CRUD, mentee daily tick list,
   check-in form/history, coach review queue.
3. **Scores + Leaderboards** — My Score screen, score & coach leaderboards,
   snapshots, trends, maintenance sweep, admin Recalculate.
4. **Coach layer** — roster, mentee detail, coaching notes + action items,
   groups admin, delegations.
5. **Engagement + Admin polish** — achievements, notifications + preferences,
   activity log, analytics dashboard, onboarding touches.

## Out of scope

- A12's web UI, Tailwind styling, and React components (screens are designed
  as native Flutter following InnerU's existing look).
- A12's JWT/bcrypt auth (InnerU already has Firebase Auth).
- Server-side enforcement of scoring integrity (accepted serverless trade-off).
- Replacing InnerU's userpoints leaderboard or personal notes (kept, per user
  decision).
- HTML note bodies and the sanitizer (coaching notes are plain text).
