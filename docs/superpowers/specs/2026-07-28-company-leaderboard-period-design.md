# Company Leaderboard Period Design

## Problem

Today, the company leaderboard (`LeaderboardController::index`) and every other
consumer of `UserScoreService` scores a user by averaging their **entire**
`DailyTracker` history with no date bounds at all
(`UserScoreService::summarizeBreakdowns`). The admin wants to run a defined
competition window per company — e.g. Gencys: Aug 1 – Dec 31, 2026 — where
the leaderboard only reflects activity from that window forward, with a
stricter scoring formula than today's "average of however many days you
happened to track."

This needs: (1) an admin-editable start/end date per company, and (2) a
scoring formula change that applies only when a company has such a period
configured.

## Decisions (resolved during brainstorming)

- **"Goals score"** = the existing `todo_list_score` / `goalScore` concept
  already computed in `UserScoreService` today (lives on the `daily_trackers`
  row). Not the separate Abundance/A12 `Goal` model system.
- **Divisor for the daily-tracker average is the period's fixed, full day
  count — always**, even mid-period. A period that hasn't finished yet will
  show low scores until it does; this is intentional, not a bug, per explicit
  user choice over the alternative (dividing by elapsed days so far).
- **Companies with no period configured, or one that was removed, are
  completely unaffected** — they keep today's all-time-average behavior
  exactly as it is now. This feature is opt-in per company.
- **The period-bounded scoring applies everywhere `UserScoreService` computes
  a score** — the company leaderboard, the coach's mentee-ranking list
  (`/api/coach/mentees`), and any other current or future consumer. One
  shared score, not a leaderboard-only fork, so a user's score can't
  disagree with itself depending on which screen shows it.
- **One period per company**, not a history table. Editing replaces the
  existing dates; there is no record of past periods once replaced.
- **Day count is inclusive of both boundary dates**: Aug 1 – Dec 31, 2026 is
  153 days (31+30+31+30+31), not 152. Confirmed directly against the
  example — the "152" in the original request was an estimate, not an exact
  count.
- **The "goals score" is NOT period-averaged** — it's the latest available
  value, not summed-and-divided like the daily-tracker score. However, per
  the "no previous score" requirement, "latest" must still never reach back
  to a record dated before the period's start.

## Data Model

New migration, adding two nullable columns to the existing `companies` table:

```php
Schema::table('companies', function (Blueprint $table): void {
    $table->date('leaderboard_period_start')->nullable();
    $table->date('leaderboard_period_end')->nullable();
});
```

Both null = no period configured (default/current state for every existing
company). `Company::$fillable` gains both fields.

## Admin API

No new routes. Extends the existing `PATCH /api/companies/{company}`
(`CompanyController::update`), which already handles partial company edits
(name, theme, logo, etc.) via a validated array + `fillablePayload()` +
`payload()` — this feature adds three more optional fields to that same
three-part pattern:

- `leaderboardPeriodStart` (`sometimes`, `date`) — required together with
  `leaderboardPeriodEnd` when either is present (the UI always sends both
  together as one "set period" action, never a lone date).
- `leaderboardPeriodEnd` (`sometimes`, `date`, `after_or_equal:leaderboardPeriodStart`)
- `clearLeaderboardPeriod` (`sometimes`, `boolean`) — when true, sets both
  columns to null, following the exact pattern already used by
  `clearLoadingImage` / `clearLoadingVideo` in the same controller.

Response payload (`CompanyController::payload`) gains
`leaderboardPeriodStart` / `leaderboardPeriodEnd` (ISO date strings or
`null`), so the admin UI can show the company's current period without a
separate fetch.

## Admin UI

`lib/src/features/authentication/screen/adminscreen/manage_companies.dart`
(the existing company-management screen — already edits name, theme, logo,
loading media per company card) gains one more row per company card:
"Leaderboard period", showing the current range (e.g. "Aug 1 – Dec 31,
2026") or "Not set", with an edit icon.

Tapping it opens a dialog matching the file's existing
`_showEditNameDialog` structure exactly (`StatefulBuilder` for a local
saving/loading flag, `CompanyApiService.instance.updateCompany(...)` to
persist, a snackbar on success/failure, refreshing the company list after):
two date fields (start, end — Flutter's `showDatePicker`), a "Save" button
that sends both dates together, a "Cancel" button, and — only when the
company already has a period set — a "Remove period" text button that sends
`{'clearLeaderboardPeriod': true}`.

Validation before saving: both dates must be filled, end must not be before
start; otherwise show an inline error rather than calling the API.

## Scoring Logic (`UserScoreService`)

Today, `resolveBreakdownForUser` / `resolveBreakdownForUsers` fetch a user's
entire `DailyTracker` history and average via `summarizeBreakdowns`. This
changes to first check whether the user's company has a period configured:

1. **Resolve the user's company** the same way `LeaderboardController` /
   `CoachManagementController` already do — matching
   `company_id`/`company_code`/`company_name` or the `active_company_*`
   equivalents against the `companies` table.
2. **If that company has both `leaderboard_period_start` and
   `leaderboard_period_end` set:**
   - Fetch only `DailyTracker` rows for the user with `date` between those
     two dates (inclusive).
   - `coreTaskScore` = (sum of each fetched row's existing per-day
     completion-percentage calculation, i.e. the same per-row logic
     `scoreBreakdownFromDailyTracker` already uses today) ÷ (inclusive day
     count of the period — `start->diffInDays($end) + 1`). Days within the
     period with no row contribute 0 to the sum but still occupy one slot in
     that fixed divisor.
   - `goalScore` = the `goalScore` value from the `DailyTracker` row with the
     latest `date` within the period (there is exactly one row per
     `(user_id, date)` — the table's existing unique constraint — so no
     tie-break is needed). Zero if no row exists yet within the period.
     Never looks at a row dated before the period's start.
   - `overallScore = (coreTaskScore + goalScore) / 2` — same combining
     formula the codebase already uses for the non-period case.
3. **If the company has no period configured (either field null):**
   unchanged — falls through to today's existing `summarizeBreakdowns`
   all-time-average logic, byte-for-byte the same behavior as before this
   feature.

Batch efficiency (`resolveBreakdownForUsers`, used for a whole company's
leaderboard or a coach's mentee list at once): resolve each distinct
company referenced by the input users in one query rather than one query
per user, since callers of this method typically pass many users from the
same company at once.

## Out of scope

- Multiple/historical periods per company (explicitly declined — one
  period, edited in place).
- Any change to how a user's own daily/profile score displays outside of
  `UserScoreService`'s consumers (e.g. the Profile page's own
  `_dailyTrackerScore`/`_combinedDailyAndTodoScore`, which computes
  independently client-side and was untouched by this feature).
- Any change to the Abundance/A12-specific scoring engine
  (`lib/src/features/abundance/domain/scoring.dart`), which is a separate
  system from `UserScoreService` entirely.

## Testing

- Backend: new `backend/tests/Feature/CompanyLeaderboardPeriodApiTest.php`
  covering the admin API — setting a period, requiring both dates together,
  rejecting end-before-start, clearing a period, and the response payload
  shape.
- Backend: new `backend/tests/Feature/UserScorePeriodTest.php` covering
  `UserScoreService` directly — a user with tracker data before, during, and
  after a configured period (only "during" counts), the fixed
  full-period-length divisor (not elapsed-days), the "latest goalScore
  within period, never before it" rule, and a company with no period
  configured behaving exactly as it does today (regression check against
  existing behavior).
- No frontend widget test for the new admin dialog — consistent with this
  codebase's existing convention for `manage_companies.dart` and other
  admin/Firebase-network-backed screens (no existing widget test for this
  file); verified via `flutter analyze` and a manual run-through.
