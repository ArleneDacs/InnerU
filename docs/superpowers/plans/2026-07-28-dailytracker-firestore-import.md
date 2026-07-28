# DailyTracker Firestore Historical Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** backfill the historical Firestore `dailytracker` collection into the already-live `daily_trackers` Postgres table, without touching the app or the live API, and without ever overwriting real production data already written since the 2026-07-21 cutover.

**Architecture:** add a 7th importer (`DailyTrackerImporter`) to the existing `FirestoreImport` pipeline (`backend/app/Services/FirestoreImport/`), following the exact interface and conventions of the 6 already built (`UserImporter`, `CoachRelationshipImporter`, `GoalImporter`, `NotesImporter`, `WellnessImporter`, `UserPointsImporter`). Add the Firestore collection to the export script's collection list, re-run the real production export, verify the field mapping against real data, then run the import.

**Tech Stack:** Laravel (PHP), PHPUnit, Node.js (`firebase-admin`) for the export script, Postgres + SQLite (test DB).

## Global Constraints

- **Design doc:** `docs/superpowers/specs/2026-07-28-dailytracker-firestore-import-design.md` — read it before starting; every task below implements a specific section of it.
- **Never overwrite an existing `daily_trackers` row.** If a row already exists for `(user_id, date)`, skip the Firestore record entirely — do not update it. This is the one deliberate behavioral difference from the other 6 importers.
- **NOT NULL guards:** `daily_trackers.username` and `daily_trackers.date` are `NOT NULL` with no DB default. `date` missing → skip the whole record (can't file it under any day). `username` missing → default to `''` (matches `UserPointsImporter`'s exact precedent — it does not skip on missing username, only on missing user match or missing date).
- **Never assign `?? null` to a NOT NULL/has-a-default column.** Every count/boolean column on `daily_trackers` has a DB default; missing source fields map to `?? 0` / `?? false` in code, and every numeric field is coerced with `(int) round(...)` to survive fractional values from real historical data (this exact bug class — a float landing on an integer column — has hit this codebase 3 times already: the Firestore importer's own `UserPointsImporter`, and the live `DailyTrackerController`/`UserPointController` scoring endpoints, fixed 2026-07-27).
- **Commit workflow:** per-task commits, approved as a scoped exception to the project's normal no-commit rule (same as the 2026-07-25 migration).
- **Full suite must pass on both SQLite and Postgres** before any task is considered done: `cd backend && php artisan test` (SQLite, default) and `cd backend && ./vendor/bin/phpunit --configuration=phpunit.pgsql.xml` (real Postgres — note `php artisan test --configuration=X` is broken in this project; always invoke `vendor/bin/phpunit` directly for the Postgres run).
- **Tasks 4 and 5 require live production Firestore credentials and are executed by the controller directly in this session, not dispatched to a fresh subagent** (per the user's explicit choice during brainstorming). Tasks 1–3 are self-contained and are good subagent-driven-development candidates.

---

### Task 1: Add `dailytracker` to the Firestore export collection list

**Files:**
- Modify: `scripts/firestore-export/export-firestore.js:23-31`

**Interfaces:**
- Consumes: nothing new.
- Produces: when `node export-firestore.js <service-account.json> [outDir]` is run, it now also writes `<outDir>/dailytracker.json` — the file `DailyTrackerImporter` (Task 2) reads via `SnapshotReader::collection('dailytracker')`.

- [ ] **Step 1: Add the collection to the list**

In `scripts/firestore-export/export-firestore.js`, change:

```js
const TOP_LEVEL_COLLECTIONS = [
  'users',
  'coaches',
  'coach_groups',
  'coach_requests',
  'goals',
  'notes',
  'userpoints',
];
```

to:

```js
const TOP_LEVEL_COLLECTIONS = [
  'users',
  'coaches',
  'coach_groups',
  'coach_requests',
  'goals',
  'notes',
  'userpoints',
  'dailytracker',
];
```

- [ ] **Step 2: Run the existing export script tests to confirm nothing broke**

Run: `cd scripts/firestore-export && npm test`
Expected: PASS (all existing `serializeValue` tests unaffected — this file has no test that enumerates `TOP_LEVEL_COLLECTIONS`, so no test changes are needed for this step).

- [ ] **Step 3: Commit**

```bash
git add scripts/firestore-export/export-firestore.js
git commit -m "feat: include dailytracker collection in Firestore export"
```

---

### Task 2: `DailyTrackerImporter` (historical daily tracker backfill)

**Files:**
- Create: `backend/app/Services/FirestoreImport/DailyTrackerImporter.php`
- Test: `backend/tests/Feature/FirestoreImport/DailyTrackerImporterTest.php`

**Interfaces:**
- Consumes: `SnapshotReader::collection('dailytracker')` (returns `array<int, array{id: string, data: array}>`, `[]` if the file doesn't exist — see `backend/app/Services/FirestoreImport/SnapshotReader.php:11-14`); `App\Models\User` (matches via `firebase_uid`); `App\Models\DailyTracker` (the target model, see its `$fillable`/casts at `backend/app/Models/DailyTracker.php`); `ImportReport::increment(string $collection, string $bucket)` / `::skip(string $collection, string $sourceId, string $reason)`.
- Produces: `DailyTrackerImporter::import(bool $dryRun): void` — matches the exact interface every other importer in `Task 15`'s `importers()` array already follows (see `backend/app/Console/Commands/ImportFirestoreData.php:74-87`), so Task 3 can wire it in with one line.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/Feature/FirestoreImport/DailyTrackerImporterTest.php`:

```php
<?php
// backend/tests/Feature/FirestoreImport/DailyTrackerImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\DailyTracker;
use App\Models\User;
use App\Services\FirestoreImport\DailyTrackerImporter;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class DailyTrackerImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/dailytracker-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_historical_record_for_a_matching_user(): void
    {
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/dailytracker.json", json_encode([
            ['id' => 'uid-1_2025-03-01', 'data' => [
                'userId' => 'uid-1', 'date' => '2025-03-01', 'username' => 'Jane',
                'call' => true, 'steps' => true, 'exercise' => false,
                'meditation' => true, 'learning' => false, 'addValue' => true,
                'stepCount' => 8000, 'stepGoal' => 10000,
            ]],
        ]));

        $importer = new DailyTrackerImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $record = DailyTracker::where('user_id', $user->id)->where('date', '2025-03-01')->first();
        $this->assertNotNull($record);
        $this->assertSame('Jane', $record->username);
        $this->assertTrue($record->call);
        $this->assertTrue($record->steps);
        $this->assertFalse($record->exercise);
        $this->assertTrue($record->meditation);
        $this->assertFalse($record->learning);
        $this->assertTrue($record->add_value);
        $this->assertSame(8000, $record->step_count);
        $this->assertSame(10000, $record->step_goal);
    }

    public function test_skips_a_record_with_no_matching_user(): void
    {
        File::put("{$this->dir}/dailytracker.json", json_encode([
            ['id' => 'x', 'data' => ['userId' => 'missing-uid', 'date' => '2025-03-01']],
        ]));

        $report = new ImportReport();
        $importer = new DailyTrackerImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, DailyTracker::count());
        $this->assertNotEmpty($report->skippedRecords());
    }

    public function test_skips_a_record_with_no_date(): void
    {
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/dailytracker.json", json_encode([
            ['id' => 'x', 'data' => ['userId' => 'uid-1']],
        ]));

        $report = new ImportReport();
        $importer = new DailyTrackerImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, DailyTracker::where('user_id', $user->id)->count());
        $this->assertNotEmpty($report->skippedRecords());
    }

    public function test_never_overwrites_an_existing_row_for_the_same_user_and_date(): void
    {
        // daily_trackers has a live production writer (DailyTrackerController)
        // active since the 2026-07-21 cutover. A historical Firestore record
        // for a date that already has real Postgres data must never clobber
        // it.
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);
        $existing = DailyTracker::create([
            'user_id' => $user->id,
            'username' => 'Live Data',
            'date' => '2026-07-22',
            'step_count' => 12345,
            'call' => true,
        ]);

        File::put("{$this->dir}/dailytracker.json", json_encode([
            ['id' => 'uid-1_2026-07-22', 'data' => [
                'userId' => 'uid-1', 'date' => '2026-07-22', 'username' => 'Stale Firestore Data',
                'stepCount' => 1, 'call' => false,
            ]],
        ]));

        $report = new ImportReport();
        $importer = new DailyTrackerImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(1, DailyTracker::where('user_id', $user->id)->where('date', '2026-07-22')->count());
        $existing->refresh();
        $this->assertSame('Live Data', $existing->username);
        $this->assertSame(12345, $existing->step_count);
        $this->assertTrue($existing->call);
        $this->assertNotEmpty($report->skippedRecords());
    }

    public function test_rounds_fractional_values_for_integer_columns_instead_of_failing(): void
    {
        // Proactive guard, matching this project's own precedent (the
        // Task 13 NOT-NULL audit) of fixing this bug class before it's
        // observed in this specific table, rather than waiting to get
        // bitten a 4th time (already hit in UserPointsImporter and the
        // live DailyTrackerController/UserPointController scoring APIs).
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/dailytracker.json", json_encode([
            ['id' => 'uid-1_2025-03-01', 'data' => [
                'userId' => 'uid-1', 'date' => '2025-03-01', 'username' => 'Jane',
                'stepCount' => 8000.7, 'exerciseMinutes' => 15.5, 'userTotalScore' => 55.5,
            ]],
        ]));

        $importer = new DailyTrackerImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $record = DailyTracker::where('user_id', $user->id)->where('date', '2025-03-01')->first();
        $this->assertNotNull($record);
        $this->assertSame(8001, $record->step_count);
        $this->assertSame(16, $record->exercise_minutes);
        $this->assertSame(56, $record->user_total_score);
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && php artisan test --filter=DailyTrackerImporterTest`
Expected: FAIL with "Class \"App\Services\FirestoreImport\DailyTrackerImporter\" not found" (or similar autoload error) for every test.

- [ ] **Step 3: Implement `DailyTrackerImporter`**

Create `backend/app/Services/FirestoreImport/DailyTrackerImporter.php`:

```php
<?php
// backend/app/Services/FirestoreImport/DailyTrackerImporter.php

namespace App\Services\FirestoreImport;

use App\Models\DailyTracker;
use App\Models\User;

// Confirmed-real fields (from the removed pre-cutover Dart code in commit
// 8d8948b): userId, username, call, steps, exercise, meditation, learning,
// addValue, date/lastUpdated. Every other field below is inferred from the
// current Postgres schema and the current API's upsert payload shape
// (daily_tracker_api_service.dart) - confirm against a real exported
// snapshot (scripts/firestore-export/snapshot/dailytracker.json, produced
// by Task 4) before trusting this mapping in production.
class DailyTrackerImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('dailytracker') as $record) {
            $this->importRecord($record['id'], $record['data']);
        }
    }

    private function importRecord(string $firestoreId, array $data): void
    {
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        // Matches the old Dart code's _resolveTrackerDate fallback order
        // exactly: lastUpdated takes priority over date.
        $date = $data['lastUpdated'] ?? $data['date'] ?? null;
        if ($userId === null || $date === null) {
            $this->report->skip('daily_trackers', $firestoreId, 'missing matching user or date');

            return;
        }

        // daily_trackers has a live production writer (DailyTrackerController)
        // active since the 2026-07-21 cutover. Treat any existing row for
        // this user+date as authoritative and never overwrite it - this
        // importer only fills in historical gaps.
        if (DailyTracker::where('user_id', $userId)->where('date', $date)->exists()) {
            $this->report->skip('daily_trackers', $firestoreId, 'row already exists for this user and date');

            return;
        }

        $record = new DailyTracker();
        $record->user_id = $userId;
        $record->date = $date;
        $record->username = $data['username'] ?? '';
        $record->step_count = (int) round($data['stepCount'] ?? 0);
        $record->step_goal = (int) round($data['stepGoal'] ?? 5000);
        $record->meditation = (bool) ($data['meditation'] ?? false);
        $record->steps = (bool) ($data['steps'] ?? false);
        $record->call = (bool) ($data['call'] ?? false);
        $record->exercise = (bool) ($data['exercise'] ?? false);
        $record->learning = (bool) ($data['learning'] ?? false);
        $record->add_value = (bool) ($data['addValue'] ?? false);
        $record->todo_list = (bool) ($data['todoList'] ?? false);
        $record->call_count = (int) round($data['callCount'] ?? 0);
        $record->exercise_count = (int) round($data['exerciseCount'] ?? 0);
        $record->exercise_minutes = (int) round($data['exerciseMinutes'] ?? 0);
        $record->learning_count = (int) round($data['learningCount'] ?? 0);
        $record->value_count = (int) round($data['valueCount'] ?? 0);
        $record->todo_list_count = (int) round($data['todoListCount'] ?? 0);
        $record->todo_list_score = (int) round($data['todoListScore'] ?? 0);
        $record->todo_list_score_daily_contribution = (int) round($data['todoListScoreDailyContribution'] ?? 0);
        $record->todo_list_included_in_total = (bool) ($data['todoListIncludedInTotal'] ?? false);
        $record->user_total_score = (int) round($data['userTotalScore'] ?? 0);
        $record->custom_daily_tasks = $data['customDailyTasks'] ?? null;
        $record->meditation_minutes = (int) round($data['meditationMinutes'] ?? 0);
        $record->company_id = $data['companyId'] ?? null;
        $record->company_code = $data['companyCode'] ?? null;
        $record->company_name = $data['companyName'] ?? null;
        $record->save();

        $this->report->increment('daily_trackers', 'created');
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && php artisan test --filter=DailyTrackerImporterTest`
Expected: PASS (5 passed).

- [ ] **Step 5: Run the full suite on SQLite and Postgres**

Run: `cd backend && php artisan test`
Expected: PASS, all tests (no regressions).

Run: `cd backend && ./vendor/bin/phpunit --configuration=phpunit.pgsql.xml`
Expected: PASS, all tests (no regressions).

- [ ] **Step 6: Commit**

```bash
git add backend/app/Services/FirestoreImport/DailyTrackerImporter.php backend/tests/Feature/FirestoreImport/DailyTrackerImporterTest.php
git commit -m "feat: add DailyTrackerImporter for historical Firestore dailytracker backfill"
```

---

### Task 3: Wire `DailyTrackerImporter` into the `firestore:import` command

**Files:**
- Modify: `backend/app/Console/Commands/ImportFirestoreData.php:6-14` (imports), `:73-87` (`importers()`)
- Modify: `backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php`

**Interfaces:**
- Consumes: `DailyTrackerImporter` from Task 2 (constructor `(SnapshotReader $reader, ImportReport $report)`, method `import(bool $dryRun): void`).
- Produces: nothing new consumed by later tasks — this is the last code task.

- [ ] **Step 1: Write the failing test**

In `backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php`, add `use App\Models\DailyTracker;` to the imports at the top, then add this new test method inside the class (after `test_full_run_imports_a_user_and_their_goal_in_dependency_order`):

```php
    public function test_full_run_also_imports_daily_tracker_records(): void
    {
        $dir = sys_get_temp_dir().'/firestore-import-dailytracker-'.uniqid();
        File::ensureDirectoryExists($dir);

        File::put("$dir/users.json", json_encode([['id' => 'uid-1', 'data' => ['username' => 'Jane']]]));
        foreach (['coaches', 'coach_groups', 'coach_requests', 'notes', 'userpoints', 'goals'] as $name) {
            File::put("$dir/{$name}.json", json_encode([]));
        }
        File::put("$dir/dailytracker.json", json_encode([
            ['id' => 'uid-1_2025-03-01', 'data' => ['userId' => 'uid-1', 'date' => '2025-03-01', 'username' => 'Jane', 'call' => true]],
        ]));
        File::put("$dir/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-1', 'email' => 'jane@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));
        foreach (['tasks', 'updates', 'comments', 'merits', 'wellness', 'history'] as $group) {
            File::put("$dir/_group_{$group}.json", json_encode([]));
        }

        $this->artisan('firestore:import', ['--path' => $dir])
            ->expectsOutputToContain('daily_trackers: created=1')
            ->assertExitCode(0);

        $user = User::where('firebase_uid', 'uid-1')->first();
        $this->assertNotNull($user);
        $this->assertSame(1, DailyTracker::where('user_id', $user->id)->count());

        File::deleteDirectory($dir);
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && php artisan test --filter=test_full_run_also_imports_daily_tracker_records`
Expected: FAIL — `daily_trackers: created=1` never appears in the output (the importer isn't wired in yet, so the collection is silently ignored) and/or `DailyTracker::where(...)->count()` is `0` instead of `1`.

- [ ] **Step 3: Wire the importer into the command**

In `backend/app/Console/Commands/ImportFirestoreData.php`, add the import alongside the others (after `use App\Services\FirestoreImport\CoachRelationshipImporter;`, keeping alphabetical order):

```php
use App\Services\FirestoreImport\DailyTrackerImporter;
```

Then change the `importers()` method:

```php
    /** @return array<int, UserImporter|CoachRelationshipImporter|GoalImporter|NotesImporter|WellnessImporter|UserPointsImporter|DailyTrackerImporter> */
    private function importers(SnapshotReader $reader, ImportReport $report): array
    {
        // UserImporter must run first: every other importer resolves foreign
        // keys via User::where('firebase_uid', ...). The rest may run in any
        // order relative to each other.
        return [
            new UserImporter($reader, $report),
            new CoachRelationshipImporter($reader, $report),
            new GoalImporter($reader, $report),
            new NotesImporter($reader, $report),
            new WellnessImporter($reader, $report),
            new UserPointsImporter($reader, $report),
            new DailyTrackerImporter($reader, $report),
        ];
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd backend && php artisan test --filter=test_full_run_also_imports_daily_tracker_records`
Expected: PASS.

- [ ] **Step 5: Run the full suite on SQLite and Postgres**

Run: `cd backend && php artisan test`
Expected: PASS, all tests (no regressions — every other test in `ImportFirestoreDataCommandTest` builds snapshot dirs without a `dailytracker.json` file, which `SnapshotReader::collection()` safely treats as an empty collection, so they're unaffected).

Run: `cd backend && ./vendor/bin/phpunit --configuration=phpunit.pgsql.xml`
Expected: PASS, all tests (no regressions).

- [ ] **Step 6: Commit**

```bash
git add backend/app/Console/Commands/ImportFirestoreData.php backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php
git commit -m "feat: wire DailyTrackerImporter into firestore:import command"
```

---

### Task 4: Re-run the production export and verify the field mapping against real data

**Executor:** Controller (this session) — requires the real production Firestore credentials already present at `scripts/firestore-export/service-account.json`, and a judgment call against real (sensitive) user data. Do not dispatch this task to a fresh subagent.

**Files:**
- Possibly modify: `backend/app/Services/FirestoreImport/DailyTrackerImporter.php` and `backend/tests/Feature/FirestoreImport/DailyTrackerImporterTest.php`, only if real field names differ from the hypothesis.

- [ ] **Step 1: Re-run the export against production**

Run: `cd scripts/firestore-export && node export-firestore.js service-account.json snapshot`
Expected: prints a per-collection document count for all 8 top-level collections (including the new `dailytracker: N document(s)` line) and the 6 collection groups, ending with `Done.`.

- [ ] **Step 2: Inspect the real field names**

Run:
```bash
node -e "
const d = require('./scripts/firestore-export/snapshot/dailytracker.json');
console.log('document count:', d.length);
console.log('sample field names:', d.length ? Object.keys(d[0].data) : '(empty collection)');
console.log('sample record:', JSON.stringify(d[0] ?? null, null, 2));
"
```

- [ ] **Step 3: Compare against the hypothesis and fix if needed**

Compare the printed field names against what `DailyTrackerImporter::importRecord()` reads: `userId`, `date`, `lastUpdated`, `username`, `call`, `steps`, `exercise`, `meditation`, `learning`, `addValue`, `todoList`, `stepCount`, `stepGoal`, `callCount`, `exerciseCount`, `exerciseMinutes`, `learningCount`, `valueCount`, `todoListCount`, `todoListScore`, `todoListScoreDailyContribution`, `todoListIncludedInTotal`, `userTotalScore`, `customDailyTasks`, `meditationMinutes`, `companyId`, `companyCode`, `companyName`.

If every field name matches: no code change needed, move to Task 5.

If any field name differs (e.g. the real data uses `addvalue` instead of `addValue`, or a field is entirely absent/named differently): update the corresponding line(s) in `DailyTrackerImporter::importRecord()` to read the real field name, update the doc comment at the top of the class to state the mapping is now confirmed (removing the "unconfirmed" caveat for whichever fields were checked), and add a new regression test to `DailyTrackerImporterTest.php` using the real field shape (with realistic but non-identifying values, not real user data) to lock in the correction. Then:

Run: `cd backend && php artisan test --filter=DailyTrackerImporterTest`
Expected: PASS.

Run: `cd backend && php artisan test && cd backend && ./vendor/bin/phpunit --configuration=phpunit.pgsql.xml`
Expected: PASS, all tests, both databases.

- [ ] **Step 4: Commit (only if Step 3 required a code change)**

```bash
git add backend/app/Services/FirestoreImport/DailyTrackerImporter.php backend/tests/Feature/FirestoreImport/DailyTrackerImporterTest.php
git commit -m "fix: correct DailyTrackerImporter field mapping to match real Firestore export"
```

If Step 3 required no changes, skip this commit — there's nothing to commit.

---

### Task 5: Run the historical import

**Executor:** Controller (this session) — operates on the real production snapshot and writes to the real Postgres database. Do not dispatch this task to a fresh subagent.

- [ ] **Step 1: Dry run**

Run: `cd backend && php artisan firestore:import --path=../scripts/firestore-export/snapshot --dry-run`
Expected: prints `DRY RUN — no changes were committed.` followed by a summary line for `daily_trackers` showing `created=<N>` and, if any records were skipped, `skipped=<M>` with individual `SKIPPED daily_trackers/<id>: <reason>` lines. Read through the skip reasons — `missing matching user or date` on a handful of malformed historical docs is expected and fine; a large fraction skipped for `row already exists for this user and date` would suggest the Firestore snapshot has more overlap with live data than expected and is worth a second look before proceeding.

- [ ] **Step 2: Real run**

Run: `cd backend && php artisan firestore:import --path=../scripts/firestore-export/snapshot`
Expected: prints `Import complete.` and the same `daily_trackers: created=<N>` count as the dry run (the counts must match between dry-run and real-run — if they don't, stop and investigate before trusting the data).

- [ ] **Step 3: Spot-check the result**

Run:
```bash
cd backend && php artisan tinker --execute="
echo 'total daily_trackers rows: ' . \App\Models\DailyTracker::count() . PHP_EOL;
echo 'rows dated before 2026-07-21 (historical import): ' . \App\Models\DailyTracker::where('date', '<', '2026-07-21')->count() . PHP_EOL;
echo 'rows dated 2026-07-21 or later (live production data): ' . \App\Models\DailyTracker::where('date', '>=', '2026-07-21')->count() . PHP_EOL;
"
```
Confirm the pre-cutover count roughly matches the dry run's `created=<N>`, and that the on/after-cutover count is unchanged from before this task ran (proving no live data was touched).
