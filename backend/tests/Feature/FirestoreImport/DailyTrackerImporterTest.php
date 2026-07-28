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

    public function test_skips_a_record_with_no_userid_field_instead_of_matching_a_null_firebase_uid_user(): void
    {
        // Regression test found via Task 4's real-data verification: 97 of
        // 634 real production documents have no userId field at all.
        // Eloquent's where('firebase_uid', null) compiles to "firebase_uid
        // IS NULL", not "no match" - since firebase_uid is nullable (native
        // registrations since the 2026-07-21 cutover have no Firebase
        // account), an unguarded lookup would silently attach this record
        // to an arbitrary NULL-firebase_uid user instead of skipping it.
        $nativeUser = User::factory()->create(['firebase_uid' => null]);

        File::put("{$this->dir}/dailytracker.json", json_encode([
            ['id' => 'x', 'data' => ['date' => '2025-03-01', 'stepCount' => 500]],
        ]));

        $report = new ImportReport();
        $importer = new DailyTrackerImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, DailyTracker::where('user_id', $nativeUser->id)->count());
        $this->assertSame(0, DailyTracker::count());
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
