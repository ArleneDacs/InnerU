<?php
// backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\DailyTracker;
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

    public function test_dry_run_resolves_cross_importer_dependencies_within_the_same_run(): void
    {
        // Regression test: each importer previously ran in its own separate
        // transaction even during --dry-run, so UserImporter's dry-run-created
        // user was rolled back before GoalImporter (which resolves userId via
        // User::where('firebase_uid', ...)) ever ran — making every downstream
        // importer falsely report "no matching user" during a dry run, even
        // though a real run (where writes actually persist between importers)
        // would resolve the same user correctly.
        $dir = sys_get_temp_dir().'/firestore-import-dryrun-crossdep-'.uniqid();
        File::ensureDirectoryExists($dir);

        File::put("$dir/users.json", json_encode([['id' => 'uid-1', 'data' => ['username' => 'Jane']]]));
        foreach (['coaches', 'coach_groups', 'coach_requests', 'notes', 'userpoints'] as $name) {
            File::put("$dir/{$name}.json", json_encode([]));
        }
        File::put("$dir/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-1', 'email' => 'jane@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));
        File::put("$dir/goals.json", json_encode([
            ['id' => 'goal-1', 'data' => ['userId' => 'uid-1', 'title' => 'Read 12 books', 'category' => 'PERSONAL', 'status' => 'IN_PROGRESS', 'goalType' => 'MILESTONE', 'direction' => 'GAIN', 'targetPeriod' => 'NONE', 'startDate' => '2025-01-01', 'targetDate' => '2025-12-31']],
        ]));
        foreach (['tasks', 'updates', 'comments', 'merits', 'wellness', 'history'] as $group) {
            File::put("$dir/_group_{$group}.json", json_encode([]));
        }

        $this->artisan('firestore:import', ['--path' => $dir, '--dry-run' => true])
            ->expectsOutputToContain('goals: created=1')
            ->doesntExpectOutputToContain('SKIPPED goals/goal-1')
            ->assertExitCode(0);

        // Still a dry run: nothing persisted after the command returns.
        $this->assertSame(0, User::where('firebase_uid', 'uid-1')->count());
        $this->assertSame(0, Goal::where('firestore_id', 'goal-1')->count());

        File::deleteDirectory($dir);
    }
}
