<?php
// backend/tests/Feature/FirestoreImport/GoalImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\Goal;
use App\Models\GoalComment;
use App\Models\GoalMerit;
use App\Models\GoalTask;
use App\Models\GoalUpdate;
use App\Models\User;
use App\Services\FirestoreImport\GoalImporter;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class GoalImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/goal-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_goal_and_its_full_subcollection_family(): void
    {
        $owner = User::factory()->create(['firebase_uid' => 'owner-uid']);

        File::put("{$this->dir}/goals.json", json_encode([
            ['id' => 'goal-1', 'data' => [
                'userId' => 'owner-uid', 'title' => 'Run a marathon', 'category' => 'PERSONAL',
                'status' => 'IN_PROGRESS', 'goalType' => 'MILESTONE', 'direction' => 'GAIN',
                'targetPeriod' => 'WEEKLY', 'targetValue' => 26.2, 'currentValue' => 10, 'progress' => 40,
                'startDate' => '2025-01-01', 'targetDate' => '2025-06-01',
            ]],
        ]));
        File::put("{$this->dir}/_group_tasks.json", json_encode([
            ['id' => 'task-1', 'path' => 'goals/goal-1/tasks/task-1', 'data' => ['title' => 'Buy shoes', 'status' => 'DONE', 'isComplete' => true, 'sortOrder' => 0]],
        ]));
        File::put("{$this->dir}/_group_updates.json", json_encode([
            ['id' => 'upd-1', 'path' => 'goals/goal-1/updates/upd-1', 'data' => ['authorId' => 'owner-uid', 'progressFrom' => 10, 'progressTo' => 40, 'statusFrom' => 'NOT_STARTED', 'statusTo' => 'IN_PROGRESS']],
        ]));
        File::put("{$this->dir}/_group_comments.json", json_encode([
            ['id' => 'cmt-1', 'path' => 'goals/goal-1/comments/cmt-1', 'data' => ['authorId' => 'owner-uid', 'body' => 'Great progress!', 'isPrivate' => false]],
            ['id' => 'note-cmt-1', 'path' => 'notes/note-9/comments/note-cmt-1', 'data' => ['userId' => 'owner-uid', 'content' => 'not a goal comment']],
        ]));
        File::put("{$this->dir}/_group_merits.json", json_encode([
            ['id' => 'merit-1', 'path' => 'goals/goal-1/merits/merit-1', 'data' => ['date' => '2025-02-01', 'amount' => 3.1]],
        ]));

        $importer = new GoalImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $goal = Goal::where('firestore_id', 'goal-1')->first();
        $this->assertNotNull($goal);
        $this->assertSame($owner->id, $goal->user_id);
        $this->assertSame('Run a marathon', $goal->title);

        $this->assertSame(1, GoalTask::where('goal_id', $goal->id)->count());
        $this->assertSame(1, GoalUpdate::where('goal_id', $goal->id)->count());
        $this->assertSame(1, GoalComment::where('goal_id', $goal->id)->count());
        $this->assertSame(0, GoalComment::where('firestore_id', 'note-cmt-1')->count(), 'note comments must not leak into goal_comments');

        $merit = GoalMerit::where('firestore_id', 'merit-1')->first();
        $this->assertNotNull($merit);
        $this->assertSame($goal->user_id, $merit->user_id);
    }

    public function test_skips_a_goal_with_no_matching_user(): void
    {
        File::put("{$this->dir}/goals.json", json_encode([
            ['id' => 'goal-2', 'data' => ['userId' => 'missing-uid', 'title' => 'Orphan goal']],
        ]));
        File::put("{$this->dir}/_group_tasks.json", json_encode([]));
        File::put("{$this->dir}/_group_updates.json", json_encode([]));
        File::put("{$this->dir}/_group_comments.json", json_encode([]));
        File::put("{$this->dir}/_group_merits.json", json_encode([]));

        $report = new ImportReport();
        $importer = new GoalImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, Goal::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
