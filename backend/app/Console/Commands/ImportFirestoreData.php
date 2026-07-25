<?php
// backend/app/Console/Commands/ImportFirestoreData.php

namespace App\Console\Commands;

use App\Services\FirestoreImport\CoachRelationshipImporter;
use App\Services\FirestoreImport\DryRunAbort;
use App\Services\FirestoreImport\GoalImporter;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\NotesImporter;
use App\Services\FirestoreImport\SnapshotReader;
use App\Services\FirestoreImport\UserImporter;
use App\Services\FirestoreImport\UserPointsImporter;
use App\Services\FirestoreImport\WellnessImporter;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class ImportFirestoreData extends Command
{
    protected $signature = 'firestore:import {--path=} {--dry-run}';

    protected $description = 'Import a Firestore snapshot (see scripts/firestore-export) into Postgres.';

    public function handle(): int
    {
        $path = $this->option('path') ?: storage_path('app/firestore-snapshot');

        if (! is_dir($path)) {
            $this->error("Snapshot path does not exist: {$path}");

            return self::FAILURE;
        }

        $dryRun = (bool) $this->option('dry-run');
        $reader = new SnapshotReader($path);
        $report = new ImportReport();

        foreach ($this->importers($reader, $report) as $importer) {
            try {
                DB::transaction(function () use ($importer, $dryRun): void {
                    $importer->import($dryRun);
                    if ($dryRun) {
                        throw new DryRunAbort();
                    }
                });
            } catch (DryRunAbort) {
                // Expected for --dry-run: the transaction rolled back on purpose.
            }
        }

        $this->line($dryRun ? 'DRY RUN — no changes were committed.' : 'Import complete.');
        $this->line($report->summary());

        return self::SUCCESS;
    }

    /** @return array<int, UserImporter|CoachRelationshipImporter|GoalImporter|NotesImporter|WellnessImporter|UserPointsImporter> */
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
        ];
    }
}
