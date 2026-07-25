<?php
// backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\Goal;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class ImportFirestoreDataCommandTest extends TestCase
{
    use RefreshDatabase;

    public function test_command_reports_missing_snapshot_path(): void
    {
        $this->artisan('firestore:import', ['--path' => '/nonexistent/path'])
            ->expectsOutputToContain('Snapshot path does not exist')
            ->assertExitCode(1);
    }

    public function test_command_runs_and_prints_a_summary_for_an_empty_snapshot(): void
    {
        $dir = sys_get_temp_dir().'/firestore-import-test-'.uniqid();
        File::ensureDirectoryExists($dir);

        $this->artisan('firestore:import', ['--path' => $dir])
            ->expectsOutputToContain('Import complete')
            ->assertExitCode(0);

        File::deleteDirectory($dir);
    }

    public function test_full_run_imports_a_user_and_their_goal_in_dependency_order(): void
    {
        $dir = sys_get_temp_dir().'/firestore-import-e2e-'.uniqid();
        File::ensureDirectoryExists($dir);

        File::put("$dir/users.json", json_encode([['id' => 'uid-1', 'data' => ['username' => 'Jane']]]));
        File::put("$dir/coaches.json", json_encode([]));
        File::put("$dir/coach_groups.json", json_encode([]));
        File::put("$dir/coach_requests.json", json_encode([]));
        File::put("$dir/notes.json", json_encode([]));
        File::put("$dir/userpoints.json", json_encode([]));
        File::put("$dir/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-1', 'email' => 'jane@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));
        File::put("$dir/goals.json", json_encode([
            ['id' => 'goal-1', 'data' => ['userId' => 'uid-1', 'title' => 'Read 12 books', 'category' => 'PERSONAL', 'status' => 'IN_PROGRESS', 'goalType' => 'MILESTONE', 'direction' => 'GAIN', 'targetPeriod' => 'NONE', 'startDate' => '2025-01-01', 'targetDate' => '2025-12-31']],
        ]));
        foreach (['tasks', 'updates', 'comments', 'merits', 'wellness', 'history'] as $group) {
            File::put("$dir/_group_{$group}.json", json_encode([]));
        }

        $this->artisan('firestore:import', ['--path' => $dir])
            ->assertExitCode(0);

        $user = User::where('firebase_uid', 'uid-1')->first();
        $this->assertNotNull($user);
        $this->assertSame(1, Goal::where('user_id', $user->id)->count());

        File::deleteDirectory($dir);
    }

    public function test_dry_run_does_not_persist_any_changes(): void
    {
        $dir = sys_get_temp_dir().'/firestore-import-dryrun-'.uniqid();
        File::ensureDirectoryExists($dir);
        File::put("$dir/users.json", json_encode([['id' => 'uid-9', 'data' => ['username' => 'DryRun']]]));
        foreach (['coaches', 'coach_groups', 'coach_requests', 'notes', 'userpoints', 'goals'] as $name) {
            File::put("$dir/{$name}.json", json_encode([]));
        }
        foreach (['tasks', 'updates', 'comments', 'merits', 'wellness', 'history'] as $group) {
            File::put("$dir/_group_{$group}.json", json_encode([]));
        }
        File::put("$dir/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-9', 'email' => 'dryrun@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));

        $this->artisan('firestore:import', ['--path' => $dir, '--dry-run' => true])
            ->assertExitCode(0);

        $this->assertSame(0, User::where('firebase_uid', 'uid-9')->count());

        File::deleteDirectory($dir);
    }
}
