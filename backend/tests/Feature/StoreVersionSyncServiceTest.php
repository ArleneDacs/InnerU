<?php

namespace Tests\Feature;

use App\Contracts\GooglePlayVersionFetcher;
use App\Models\AppVersion;
use App\Services\StoreVersionSyncService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Mockery;
use Tests\TestCase;

class StoreVersionSyncServiceTest extends TestCase
{
    use RefreshDatabase;

    public function test_sync_all_updates_both_platforms_on_success(): void
    {
        // Store polling owns only the latest version/store URL. An
        // administrator's force-vs-optional decision must survive it.
        AppVersion::current()->update([
            'ios_update_required' => false,
            'android_update_required' => false,
        ]);

        Http::fake([
            'itunes.apple.com/*' => Http::response([
                'results' => [
                    ['version' => '1.9.0', 'trackViewUrl' => 'https://apps.apple.com/app/id555'],
                ],
            ], 200),
        ]);

        $fetcher = Mockery::mock(GooglePlayVersionFetcher::class);
        $fetcher->shouldReceive('fetchLatestProductionVersionCode')
            ->with('com.valenin.inneru')
            ->andReturn([
                'version_code' => 50,
                'store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            ]);
        app()->instance(GooglePlayVersionFetcher::class, $fetcher);

        app(StoreVersionSyncService::class)->syncAll();

        $version = AppVersion::current();
        $this->assertSame('1.9.0', $version->ios_latest_version);
        $this->assertSame('https://apps.apple.com/app/id555', $version->ios_store_url);
        $this->assertFalse($version->ios_update_required);
        $this->assertSame(50, $version->android_latest_version_code);
        $this->assertFalse($version->android_update_required);
    }

    public function test_an_apple_failure_does_not_block_the_android_update(): void
    {
        Http::fake([
            'itunes.apple.com/*' => Http::response([], 500),
        ]);

        $fetcher = Mockery::mock(GooglePlayVersionFetcher::class);
        $fetcher->shouldReceive('fetchLatestProductionVersionCode')
            ->andReturn([
                'version_code' => 51,
                'store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            ]);
        app()->instance(GooglePlayVersionFetcher::class, $fetcher);

        $originalIosVersion = AppVersion::current()->ios_latest_version;

        app(StoreVersionSyncService::class)->syncAll();

        $version = AppVersion::current();
        $this->assertSame($originalIosVersion, $version->ios_latest_version);
        $this->assertSame(51, $version->android_latest_version_code);
    }

    public function test_a_google_failure_does_not_block_the_ios_update(): void
    {
        Http::fake([
            'itunes.apple.com/*' => Http::response([
                'results' => [
                    ['version' => '2.0.0', 'trackViewUrl' => 'https://apps.apple.com/app/id777'],
                ],
            ], 200),
        ]);

        $fetcher = Mockery::mock(GooglePlayVersionFetcher::class);
        $fetcher->shouldReceive('fetchLatestProductionVersionCode')
            ->andThrow(new \RuntimeException('Play API unavailable'));
        app()->instance(GooglePlayVersionFetcher::class, $fetcher);

        $originalAndroidCode = AppVersion::current()->android_latest_version_code;

        app(StoreVersionSyncService::class)->syncAll();

        $version = AppVersion::current();
        $this->assertSame('2.0.0', $version->ios_latest_version);
        $this->assertSame($originalAndroidCode, $version->android_latest_version_code);
    }

    public function test_a_malformed_apple_response_is_skipped_without_throwing(): void
    {
        Http::fake([
            'itunes.apple.com/*' => Http::response(['results' => []], 200),
        ]);

        $fetcher = Mockery::mock(GooglePlayVersionFetcher::class);
        $fetcher->shouldReceive('fetchLatestProductionVersionCode')->andReturn(null);
        app()->instance(GooglePlayVersionFetcher::class, $fetcher);

        $originalIosVersion = AppVersion::current()->ios_latest_version;

        app(StoreVersionSyncService::class)->syncAll();

        $this->assertSame($originalIosVersion, AppVersion::current()->ios_latest_version);
    }
}
