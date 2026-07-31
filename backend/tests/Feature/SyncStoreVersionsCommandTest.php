<?php

namespace Tests\Feature;

use App\Services\StoreVersionSyncService;
use Mockery;
use Tests\TestCase;

class SyncStoreVersionsCommandTest extends TestCase
{
    public function test_it_delegates_to_the_sync_service(): void
    {
        $syncService = Mockery::mock(StoreVersionSyncService::class);
        $syncService->shouldReceive('syncAll')->once();
        app()->instance(StoreVersionSyncService::class, $syncService);

        $this->artisan('app:sync-store-versions')->assertExitCode(0);
    }
}
