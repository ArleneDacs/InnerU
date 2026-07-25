<?php
// backend/tests/Feature/FirestoreImport/CoachRelationshipImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\CoachRequest;
use App\Models\User;
use App\Services\FirestoreImport\CoachRelationshipImporter;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class CoachRelationshipImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/coach-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_group_request_and_synthesizes_mentee_relationship_with_group(): void
    {
        $coach = User::factory()->create(['firebase_uid' => 'coach-uid', 'is_coach' => true]);
        $mentee = User::factory()->create(['firebase_uid' => 'mentee-uid']);

        File::put("{$this->dir}/coach_groups.json", json_encode([
            ['id' => 'group-1', 'data' => ['coachId' => 'coach-uid', 'name' => 'Morning Crew', 'memberIds' => ['mentee-uid'], 'memberCount' => 1]],
        ]));
        File::put("{$this->dir}/coach_requests.json", json_encode([
            ['id' => 'req-1', 'data' => [
                'coachId' => 'coach-uid', 'menteeId' => 'mentee-uid', 'menteeName' => 'Mentee Name',
                'menteeEmail' => 'mentee@example.com', 'status' => 'accepted', 'applyingAs' => 'mentee',
            ]],
        ]));
        File::put("{$this->dir}/users.json", json_encode([
            ['id' => 'mentee-uid', 'data' => ['coachIds' => ['coach-uid']]],
        ]));

        $importer = new CoachRelationshipImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $group = CoachGroup::where('firestore_id', 'group-1')->first();
        $this->assertNotNull($group);
        $this->assertSame((string) $coach->id, (string) $group->coach_id);
        $this->assertSame(1, $group->member_count);

        $request = CoachRequest::where('firestore_id', 'req-1')->first();
        $this->assertNotNull($request);
        $this->assertSame('accepted', $request->status);

        $relation = CoachMentee::where('coach_id', (string) $coach->id)->where('mentee_id', (string) $mentee->id)->first();
        $this->assertNotNull($relation);
        $this->assertSame($group->id, $relation->group_id);
        $this->assertSame('Morning Crew', $relation->group_name);
    }

    public function test_skips_a_group_with_no_matching_coach(): void
    {
        File::put("{$this->dir}/coach_groups.json", json_encode([
            ['id' => 'group-1', 'data' => ['coachId' => 'missing-uid', 'name' => 'Orphan Group']],
        ]));
        File::put("{$this->dir}/coach_requests.json", json_encode([]));
        File::put("{$this->dir}/users.json", json_encode([]));

        $report = new ImportReport();
        $importer = new CoachRelationshipImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, CoachGroup::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
