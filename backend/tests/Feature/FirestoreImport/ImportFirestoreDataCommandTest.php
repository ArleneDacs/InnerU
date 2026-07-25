<?php
// backend/tests/Feature/FirestoreImport/ImportFirestoreDataCommandTest.php

namespace Tests\Feature\FirestoreImport;

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
}
