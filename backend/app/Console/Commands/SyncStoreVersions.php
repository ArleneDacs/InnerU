<?php

namespace App\Console\Commands;

use App\Services\StoreVersionSyncService;
use Illuminate\Console\Command;

class SyncStoreVersions extends Command
{
    protected $signature = 'app:sync-store-versions';

    protected $description = 'Check Apple and Google for the latest published app versions and update the app_versions record.';

    public function handle(StoreVersionSyncService $syncService): int
    {
        $syncService->syncAll();

        $this->info('Store versions synced.');

        return self::SUCCESS;
    }
}
