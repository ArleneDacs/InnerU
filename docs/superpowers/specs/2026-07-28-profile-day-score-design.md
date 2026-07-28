# Profile "View Previous Progress" — per-day score

## Problem

In the user's own Profile screen, the "View Previous Progress" section
(`_buildCalendar` in `lib/src/features/authentication/screen/profile/profile.dart`)
shows a calendar for past months. Tapping a day opens a dialog
(`_showDailyTrackerDialog`) listing that day's daily-tracker checklist
items as read-only checkboxes — but it never shows what percentage of
the day's tasks were actually completed. The user wants to see that
day's score (e.g. "July 21 → 20%", "July 22 → 100%") when they tap a
day.

## Existing scoring concept (no new logic needed)

The app already computes and persists a 0–100 daily score:

- `DailyTracker.user_total_score` (backend column, `backend/app/Models/DailyTracker.php`)
  is written on every upsert (`DailyTrackerController::upsert`) and is the
  same score `profile.dart` computes for *today* client-side as
  `_combinedDailyAndTodoScore` (`_dailyTrackerScore`, optionally averaged
  with the todo-list score) before syncing.
- `DailyTrackerController::mapTracker()` already returns this value as
  `userTotalScore` in every tracker JSON payload — including the single
  day fetch (`GET /api/daily-tracker?date=...`) that `_showDailyTrackerDialog`
  already calls via `DailyTrackerApiService.instance.fetch(date: ...)`.
- The Firestore→Postgres historical import (`DailyTrackerImporter`,
  `docs/superpowers/plans/2026-07-28-dailytracker-firestore-import.md`)
  carries `userTotalScore` over from the original Firestore documents, so
  the field is populated for imported historical days too, not just new
  Postgres-native ones.

So this field is already fetched by the code path in question and simply
isn't being read. No backend change, no new endpoint, no new scoring
computation — just read one more key out of the response already in hand.

## Change

Scope: `_showDailyTrackerDialog(int day)` in `profile.dart` only.

1. After fetching `response['tracker']`, also read
   `(data['userTotalScore'] as num?)` when `data is Map<String, dynamic>`,
   defaulting to `0` if the value is somehow absent — the backend column
   itself defaults to 0, so a genuinely missing key should be rare, but
   the read should not crash or show blank text if it happens.
2. Track whether a tracker record existed for that day at all (it already
   effectively does — the current code has an `else` branch for "no data
   found" that only logs to the console).
3. In the dialog content, above the existing checklist, add a score row:
   - If a record exists: show the day's score, e.g. `"Score: 20%"`,
     paired with a thin `LinearProgressIndicator` — reusing the same
     visual language as `_buildDailyTrackerScore` (today's score display
     elsewhere on this same page), so it reads as the same concept rather
     than a new one.
   - If no record exists for that day: show `"No tracker data recorded
     for this day"` instead of a score. (0% — did nothing that day — and
     no record — never opened the tracker that day — are different
     things, and the fetch already distinguishes them; the UI just never
     surfaced it.)
4. No changes to the calendar grid cells themselves, no month-level
   average, no new API calls (the dialog already fetches this exact
   record).

## Out of scope

- Calendar cell styling/heatmap (explicitly declined during brainstorming
  — score only shows in the tap-through dialog).
- A single aggregate "average for the month" number (explicitly declined
  — per-day only).
- The separate "Friends Tracker" screen (`daily_tracker.dart` /
  `UserProgressPage`), which shows other users' raw task checkmarks, not
  scores, and wasn't part of this request.
- Any change to how `userTotalScore` itself is computed or synced.

## Testing

- `DailyTrackerController::mapTracker` already includes `userTotalScore`
  and already has backend test coverage for that field elsewhere; no
  backend change means no new backend test is needed.
- This screen has no existing widget test (consistent with other
  Firebase/network-backed screens in this codebase); verify manually by
  running the app, opening a past day with a saved score, and confirming
  the percentage shown matches the stored value, plus checking a day with
  no record shows the "no data" message instead of 0%.
