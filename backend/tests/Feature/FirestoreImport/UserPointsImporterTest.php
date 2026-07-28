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

    public function test_two_records_for_the_same_user_and_date_but_different_companies_produce_separate_rows(): void
    {
        $user = User::factory()->create(['firebase_uid' => 'uid-2']);

        File::put("{$this->dir}/userpoints.json", json_encode([
            ['id' => 'uid-2_2025-04-01_co-1', 'data' => [
                'userId' => 'uid-2', 'date' => '2025-04-01', 'username' => 'Jane',
                'totalPoints' => 10, 'companyId' => 'co-1', 'companyCode' => 'ABC', 'companyName' => 'Acme',
            ]],
            ['id' => 'uid-2_2025-04-01_co-2', 'data' => [
                'userId' => 'uid-2', 'date' => '2025-04-01', 'username' => 'Jane',
                'totalPoints' => 20, 'companyId' => 'co-2', 'companyCode' => 'XYZ', 'companyName' => 'Globex',
            ]],
        ]));

        $importer = new UserPointsImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $records = UserPoint::where('user_id', $user->id)->where('date', '2025-04-01')->get();
        $this->assertCount(2, $records);

        $co1 = $records->firstWhere('company_id', 'co-1');
        $co2 = $records->firstWhere('company_id', 'co-2');
        $this->assertNotNull($co1);
        $this->assertNotNull($co2);
        $this->assertEqualsWithDelta(10.0, (float) $co1->total_points, 0.001);
        $this->assertEqualsWithDelta(20.0, (float) $co2->total_points, 0.001);
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

    public function test_skips_a_record_with_no_userid_field_instead_of_matching_a_null_firebase_uid_user(): void
    {
        // Regression test: 417 of 529 real production userpoints documents
        // have no userId field at all. Eloquent's where('firebase_uid',
        // null) compiles to "firebase_uid IS NULL", not "no match" - since
        // firebase_uid is nullable (native registrations since the
        // 2026-07-21 cutover have no Firebase account), an unguarded lookup
        // would silently attach this record to an arbitrary NULL-firebase_uid
        // user instead of skipping or recovering it. This doc id ("x")
        // doesn't match the {firebaseUid}-{date} recovery pattern, so it
        // must be skipped, not misattributed.
        $nativeUser = User::factory()->create(['firebase_uid' => null]);

        File::put("{$this->dir}/userpoints.json", json_encode([
            ['id' => 'x', 'data' => ['date' => '2025-04-01', 'totalPoints' => 10]],
        ]));

        $report = new ImportReport();
        $importer = new UserPointsImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, UserPoint::where('user_id', $nativeUser->id)->count());
        $this->assertSame(0, UserPoint::count());
        $this->assertNotEmpty($report->skippedRecords());
    }

    public function test_recovers_the_real_user_from_the_document_id_when_userid_field_is_missing(): void
    {
        // Every one of the 417 real documents missing userId has a document
        // ID matching {firebaseUid}-{date} (e.g.
        // "1FnRnpxZpMSblary0vBNXHuH1993-2026-07-20"), and 343 of those 417
        // extracted UIDs are real, existing users - this is how their
        // "vanished" historical points data is actually recovered, instead
        // of being permanently skipped.
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/userpoints.json", json_encode([
            ['id' => 'uid-1-2025-04-01', 'data' => ['date' => '2025-04-01', 'username' => 'Jane', 'totalPoints' => 42]],
        ]));

        $importer = new UserPointsImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $record = UserPoint::where('user_id', $user->id)->where('date', '2025-04-01')->first();
        $this->assertNotNull($record);
        $this->assertSame('Jane', $record->username);
        $this->assertEqualsWithDelta(42.0, (float) $record->total_points, 0.001);
    }

    public function test_rounds_fractional_values_for_integer_columns_instead_of_failing(): void
    {
        // Regression test: a real production userpoints record had
        // userTotalScore: 55.5 (matching totalPoints) even though
        // user_total_score is an integer column with no default cast -
        // saving it as-is threw an uncaught Postgres type error.
        $user = User::factory()->create(['firebase_uid' => 'uid-1']);

        File::put("{$this->dir}/userpoints.json", json_encode([
            ['id' => 'uid-1_2026-07-21', 'data' => [
                'userId' => 'uid-1', 'date' => '2026-07-21', 'username' => 'Arlene1233',
                'totalPoints' => 55.5, 'activityPoints' => 79.4, 'dailyTrackerScore' => 100,
                'todoListScore' => 11, 'todoListScoreDailyContribution' => 11,
                'todoListIncludedInTotal' => true, 'userTotalScore' => 55.5,
            ]],
        ]));

        $importer = new UserPointsImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $record = UserPoint::where('user_id', $user->id)->where('date', '2026-07-21')->first();
        $this->assertNotNull($record);
        $this->assertSame(56, $record->user_total_score);
        $this->assertSame(79, $record->activity_points);
        $this->assertEqualsWithDelta(55.5, (float) $record->total_points, 0.001);
    }
}
