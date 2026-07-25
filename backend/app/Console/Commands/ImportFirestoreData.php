<?php
// backend/app/Console/Commands/ImportFirestoreData.php

namespace App\Console\Commands;

use App\Services\FirestoreImport\DryRunAbort;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
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

    /** @return array<int, object{import: callable(bool): void}> */
    private function importers(SnapshotReader $reader, ImportReport $report): array
    {
        // Populated in Task 15 once every Importer class exists.
        return [];
    }
}
