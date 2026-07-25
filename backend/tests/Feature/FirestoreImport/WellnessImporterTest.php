<?php
// backend/tests/Feature/FirestoreImport/WellnessImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\FastingHistory;
use App\Models\User;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use App\Services\FirestoreImport\WellnessImporter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class WellnessImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/wellness-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_the_fasting_doc_onto_the_user_and_history_entries_into_fasting_history(): void
    {
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/_group_wellness.json", json_encode([
            ['id' => 'fasting', 'path' => 'users/uid-1/wellness/fasting', 'data' => [
                'targetHours' => 16, 'startTime' => '2025-04-01T08:00:00.000Z',
                'endTime' => null, 'lastCompletedAt' => '2025-03-30T08:00:00.000Z',
            ]],
        ]));
        File::put("{$this->dir}/_group_history.json", json_encode([
            ['id' => 'hist-1', 'path' => 'users/uid-1/wellness/fasting/history/hist-1', 'data' => [
                'targetHours' => 16, 'startTime' => '2025-03-29T08:00:00.000Z', 'plannedEndTime' => '2025-03-30T00:00:00.000Z',
                'finishedAt' => '2025-03-30T08:00:00.000Z', 'completedHours' => 24.0, 'completedTarget' => true,
                'createdAt' => '2025-03-30T08:00:00.000Z',
            ]],
        ]));

        $importer = new WellnessImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $user->refresh();
        $this->assertSame(16, $user->fasting_target_hours);
        $this->assertNotNull($user->fasting_start_at);
        $this->assertNull($user->fasting_end_at);
        $this->assertNotNull($user->fasting_last_completed_at);

        $entry = FastingHistory::where('firestore_id', 'hist-1')->first();
        $this->assertNotNull($entry);
        $this->assertSame($user->id, $entry->user_id);
        $this->assertSame(16, $entry->target_hours);
        $this->assertTrue((bool) $entry->completed_target);
        $this->assertEqualsWithDelta(24.0, (float) $entry->completed_hours, 0.001);
    }

    public function test_skips_history_entries_with_no_matching_user(): void
    {
        File::put("{$this->dir}/_group_wellness.json", json_encode([]));
        File::put("{$this->dir}/_group_history.json", json_encode([
            ['id' => 'hist-1', 'path' => 'users/missing-uid/wellness/fasting/history/hist-1', 'data' => ['targetHours' => 16]],
        ]));

        $report = new ImportReport();
        $importer = new WellnessImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, FastingHistory::count());
        $this->assertNotEmpty($report->skippedRecords());
    }

    public function test_skips_history_entries_with_no_finished_at_instead_of_crashing(): void
    {
        // fasting_history.finished_at is NOT NULL with no default (see
        // 2026_07_21_000013_create_fasting_history_table.php). A real Firestore
        // history doc for an in-progress/abandoned fast that never got a
        // `_endFast` write would be missing `finishedAt`. Saving that record with
        // finished_at = null would throw an uncaught NOT NULL violation and, since
        // the import command wraps each importer's import() call in one
        // transaction, roll back the entire WellnessImporter batch. This must be
        // skipped instead, matching GoalImporter's guard style for its own
        // required-field gaps (missing startDate/targetDate, missing merit date).
        User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/_group_wellness.json", json_encode([]));
        File::put("{$this->dir}/_group_history.json", json_encode([
            ['id' => 'hist-abandoned', 'path' => 'users/uid-1/wellness/fasting/history/hist-abandoned', 'data' => [
                'targetHours' => 16, 'startTime' => '2025-03-29T08:00:00.000Z',
                'plannedEndTime' => '2025-03-30T00:00:00.000Z',
                // no finishedAt — fast was never completed/ended
                'completedHours' => 0, 'completedTarget' => false,
            ]],
        ]));

        $report = new ImportReport();
        $importer = new WellnessImporter(new SnapshotReader($this->dir), $report);

        $baseline = FastingHistory::count();
        $importer->import(false);

        $this->assertSame($baseline, FastingHistory::count(), 'no row should be saved for a missing finished_at');
        $this->assertNull(FastingHistory::where('firestore_id', 'hist-abandoned')->first());

        $skipped = $report->skippedRecords();
        $this->assertNotEmpty($skipped);
        $matches = array_filter($skipped, fn (array $row) => $row[0] === 'fasting_history' && $row[1] === 'hist-abandoned');
        $this->assertNotEmpty($matches, 'expected a skip log entry for fasting_history/hist-abandoned');
        [, , $reason] = array_values($matches)[0];
        $this->assertStringContainsString('finishedAt', $reason);
    }
}
