<?php

namespace App\Services;

use App\Contracts\GooglePlayVersionFetcher;
use App\Models\AppVersion;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Throwable;

class StoreVersionSyncService
{
    public function __construct(private readonly GooglePlayVersionFetcher $playFetcher)
    {
    }

    public function syncAll(): void
    {
        $this->syncIosVersion();
        $this->syncAndroidVersion();
    }

    public function syncIosVersion(): void
    {
        $bundleId = config('services.apple.bundle_id');

        try {
            $response = Http::timeout(10)->get('https://itunes.apple.com/lookup', [
                'bundleId' => $bundleId,
            ]);

            $results = $response->json('results') ?? [];
            $result = $results[0] ?? null;
            $version = $result['version'] ?? null;

            if ($version === null) {
                Log::warning("iTunes lookup for {$bundleId} returned no usable version.");
                return;
            }

            $appVersion = AppVersion::current();
            $appVersion->ios_latest_version = $version;
            if (! empty($result['trackViewUrl'])) {
                $appVersion->ios_store_url = $result['trackViewUrl'];
            }
            $appVersion->save();
        } catch (Throwable $e) {
            Log::warning('Failed to sync iOS store version.', ['exception' => $e]);
        }
    }

    public function syncAndroidVersion(): void
    {
        try {
            $packageName = config('services.google_play.package_name');
            $result = $this->playFetcher->fetchLatestProductionVersionCode($packageName);

            if ($result === null) {
                Log::warning('Could not determine an Android production version this run.');
                return;
            }

            $appVersion = AppVersion::current();
            $appVersion->android_latest_version_code = $result['version_code'];
            $appVersion->android_store_url = $result['store_url'];
            $appVersion->save();
        } catch (Throwable $e) {
            Log::warning('Failed to sync Android store version.', ['exception' => $e]);
        }
    }
}
