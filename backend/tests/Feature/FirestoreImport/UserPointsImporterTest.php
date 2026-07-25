<?php
// backend/tests/Feature/FirestoreImport/UserPointsImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\User;
use App\Models\UserPoint;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use App\Services\FirestoreImport\UserPointsImporter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class UserPointsImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/userpoints-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_daily_points_record_for_a_matching_user(): void
    {
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/userpoints.json", json_encode([
            ['id' => 'uid-1_2025-04-01', 'data' => [
                'userId' => 'uid-1', 'date' => '2025-04-01', 'username' => 'Jane',
                'totalPoints' => 12.5, 'activityPoints' => 5, 'dailyTrackerScore' => 4,
                'todoListScore' => 3, 'todoListScoreDailyContribution' => 1,
                'todoListIncludedInTotal' => true, 'userTotalScore' => 100,
                'server' => 'main', 'companyId' => 'co-1', 'companyCode' => 'ABC', 'companyName' => 'Acme',
            ]],
        ]));

        $importer = new UserPointsImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $record = UserPoint::where('user_id', $user->id)->where('date', '2025-04-01')->first();
        $this->assertNotNull($record);
        $this->assertSame('Jane', $record->username);
        $this->assertEqualsWithDelta(12.5, (float) $record->total_points, 0.001);
        $this->assertSame(4, $record->daily_tracker_score);
        $this->assertTrue((bool) $record->todo_list_included_in_total);
    }

    public function test_skips_a_record_with_no_matching_user(): void
    {
        File::put("{$this->dir}/userpoints.json", json_encode([
            ['id' => 'x', 'data' => ['userId' => 'missing-uid', 'date' => '2025-04-01']],
        ]));

        $report = new ImportReport();
        $importer = new UserPointsImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, UserPoint::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
