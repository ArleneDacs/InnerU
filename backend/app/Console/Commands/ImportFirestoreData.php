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
        $importers = $this->importers($reader, $report);

        if ($dryRun) {
            // All importers must share ONE transaction for a dry run to be a
            // faithful preview: UserImporter's rows need to still exist when
            // CoachRelationshipImporter/GoalImporter/etc. resolve foreign keys
            // via User::where('firebase_uid', ...). Per-importer transactions
            // (used below for a real run) would roll back UserImporter's rows
            // before the next importer ever ran, making every downstream
            // importer report false "no matching user" skips even though a
            // real run - where each importer's writes actually persist for
            // the next one to see - would resolve them correctly.
            try {
                DB::transaction(function () use ($importers, $dryRun): void {
                    foreach ($importers as $importer) {
                        $importer->import($dryRun);
                    }
                    throw new DryRunAbort();
                });
            } catch (DryRunAbort) {
                // Expected: the whole dry run rolled back on purpose.
            }
        } else {
            foreach ($importers as $importer) {
                DB::transaction(function () use ($importer, $dryRun): void {
                    $importer->import($dryRun);
                });
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
