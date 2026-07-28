# DailyTracker Firestore → Postgres Historical Import Design

## Context

The 2026-07-25 Firestore→Postgres migration (see
`docs/superpowers/specs/2026-07-25-firestore-to-postgres-migration-design.md`)
built the `daily_trackers` Postgres table and cut the Flutter app over to a
Laravel-backed API (`DailyTrackerController`, `daily_tracker_api_service.dart`)
for all daily-tracker reads/writes. The app has zero remaining Firestore
references for this domain — new data since the cutover (commit `8d8948b`,
2026-07-21) is entirely in Postgres already.

That migration built 6 importers (`UserImporter`, `CoachRelationshipImporter`,
`GoalImporter`, `NotesImporter`, `WellnessImporter`, `UserPointsImporter`) and
exported 7 Firestore collections (`users`, `coaches`, `coach_groups`,
`coach_requests`, `goals`, `notes`, `userpoints`). It never included the
Firestore collection the pre-cutover app actually used for daily tracker data:
a top-level collection literally named `dailytracker` (confirmed from the
removed code in commit `8d8948b`, which read fields including `userId`,
`username`, `call`, `steps`, `exercise`, `meditation`, `learning`, `addValue`,
and `date`/`lastUpdated`). As a result, historical daily-tracker activity from
before the cutover was never brought into Postgres — the live table only has
data starting 2026-07-21 onward.

**Goal:** a one-time historical backfill of the old `dailytracker` Firestore
collection into the existing, live `daily_trackers` Postgres table. This is
not a new feature and does not touch the app — it only fills in historical
rows the app already knows how to read.

## Decisions made

- **One-time backfill only**, matching the pattern of the 6 existing
  importers — no ongoing dual-write, no changes to the app or the live API.
- **Same commit workflow as the July 25 migration**: subagents commit per
  task, as a scoped exception to the project's normal no-commit rule, given
  the sensitivity of the domain (real user data; the July 25 migration caught
  the same class of NOT-NULL/float-into-integer bug three separate times).
- **Production Firestore export is re-run in this session**, using the
  existing credentials and pipeline already used for the 2026-07-26 export
  (`scripts/firestore-export/`), once the importer is built and tested.
- **Collision handling: skip if a Postgres row already exists for
  `(user_id, date)`.** Postgres is treated as authoritative for any date it
  already has data for; the importer only fills in dates with no existing
  row. This is the one place this importer's behavior deliberately differs
  from the other 6: `daily_trackers` is the only migrated table with a live
  production writer that could have already written rows for dates the old
  Firestore snapshot might also cover, so overwrite-on-import (the other
  importers' behavior) would risk silently clobbering current live data.

## Architecture

A 7th importer, added to the existing `FirestoreImport` pipeline
(`backend/app/Services/FirestoreImport/`), following the same interface and
conventions as the other 6.

### Components

- `scripts/firestore-export/export-firestore.js` — add `'dailytracker'` to
  `TOP_LEVEL_COLLECTIONS`. (No test change needed —
  `export-firestore.test.js` only covers `serializeValue`.)
- `backend/app/Services/FirestoreImport/DailyTrackerImporter.php` (new) —
  same shape as `UserPointsImporter`: a single public
  `import(bool $dryRun): void`, iterating
  `$this->reader->collection('dailytracker')`.
- `backend/app/Console/Commands/ImportFirestoreData.php` — add
  `new DailyTrackerImporter($reader, $report)` to the `importers()` array.
  Order relative to the other 5 non-`UserImporter` entries doesn't matter;
  `UserImporter` must still run first (foreign keys resolve via
  `firebase_uid`).
- `backend/tests/Feature/FirestoreImport/DailyTrackerImporterTest.php` (new)
  — matching `UserPointsImporterTest.php`'s structure.
- `backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php`
  — extend to confirm the new importer is wired into the command's array.

### Matching strategy

`daily_trackers` has a unique constraint on `(user_id, date)` and — unlike
`goals`, `coach_groups`, `fasting_history`, etc. — has no `firestore_id`
column (confirmed: it's absent from
`2026_07_25_000002_add_firestore_id_columns_for_migration_import.php`).
`user_points` is in the same situation and its importer already establishes
the precedent for this case: match by resolving `user_id` via
`User::where('firebase_uid', $data['userId'])`, then
`DailyTracker::where('user_id', $userId)->where('date', $date)`. This is not
a deviation from the established pattern — it's the same approach
`UserPointsImporter` already uses for the same reason.

### Field mapping — unverified hypothesis, to confirm in Step 1

Confirmed-real fields (from the removed pre-cutover Dart code):
`userId` → resolves `user_id`, `username`, `call`, `steps`, `exercise`,
`meditation`, `learning`, `addValue` → `add_value`, `date` (falling back to
`lastUpdated` if `date` is absent, matching the old code's
`_resolveTrackerDate` logic).

Not yet confirmed against real data — inferred from the current Postgres
schema and the current API's upsert payload shape (`daily_tracker_api_service.dart`):
`step_count`, `step_goal`, `call_count`, `exercise_count`,
`exercise_minutes`, `learning_count`, `value_count`, `todo_list`,
`todo_list_count`, `todo_list_score`, `todo_list_score_daily_contribution`,
`todo_list_included_in_total`, `user_total_score`, `custom_daily_tasks`,
`meditation_minutes`, `company_id`, `company_code`, `company_name`.

This mirrors exactly how `UserPointsImporter` disclosed its own field-mapping
gap. The implementation's first step re-inspects the real re-exported
`scripts/firestore-export/snapshot/dailytracker.json` and updates the mapper
to match reality before the mapping is trusted.

### NOT NULL guards

`daily_trackers.username` and `daily_trackers.date` are `NOT NULL` with no DB
default — skip the record (via `ImportReport::skip()`) rather than aborting
the batch if either is missing, matching every other importer's guard
pattern. Every count/boolean column (`step_count`, `step_goal`, `meditation`,
`steps`, `call`, `exercise`, `learning`, `add_value`, `todo_list`,
`call_count`, `exercise_count`, `exercise_minutes`, `learning_count`,
`value_count`, `todo_list_count`, `todo_list_score`,
`todo_list_score_daily_contribution`, `todo_list_included_in_total`,
`user_total_score`, `meditation_minutes`) has a DB default, so missing
source fields map to `?? false` / `?? 0` in code — never `?? null` — to avoid
the exact float/null-into-NOT-NULL-column bug class this codebase has already
hit three times (Tasks 11, 13, and the live scoring bug fixed 2026-07-27).
`custom_daily_tasks`, `company_id`, `company_code`, and `company_name` are
nullable and pass through as-is.

## Rollout steps

1. Add `'dailytracker'` to the export script's collection list.
2. Build `DailyTrackerImporter` + its test, TDD (red → green), using
   synthetic fixtures matching the real column names/constraints.
3. Wire it into `ImportFirestoreData::importers()`; extend
   `ImportFirestoreDataCommandTest` to confirm it's included.
4. Re-run the real production export (this session, existing credentials) to
   produce `scripts/firestore-export/snapshot/dailytracker.json`; revisit the
   field mapping against real data before trusting it, exactly as Step 1
   requires.
5. Run `firestore:import --dry-run` first and inspect the report, then run
   for real.

## Testing

Unit/feature tests with synthetic fixtures against SQLite (the project's
default test DB), plus a full-suite run against real Postgres given this
codebase's history of float-into-integer bugs that only surface there.

## Rejected alternative

**Overwrite unconditionally**, matching the other 6 importers' behavior
exactly. Rejected because `daily_trackers` is the only migrated table with a
live production writer that has been active for a week before this backfill
runs — an unconditional overwrite risks silently clobbering real current data
if the frozen Firestore snapshot happens to contain any documents dated on or
after the 2026-07-21 cutover.
