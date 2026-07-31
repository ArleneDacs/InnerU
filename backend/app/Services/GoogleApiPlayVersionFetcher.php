<?php

namespace App\Services;

use App\Contracts\GooglePlayVersionFetcher;
use Google\Client as GoogleClient;
use Google\Service\AndroidPublisher;
use Google\Service\AndroidPublisher\AppEdit;
use Illuminate\Support\Facades\Log;

class GoogleApiPlayVersionFetcher implements GooglePlayVersionFetcher
{
    public function __construct(private readonly ?string $credentialsPath)
    {
    }

    public function fetchLatestProductionVersionCode(string $packageName): ?array
    {
        if (empty($this->credentialsPath) || ! is_readable($this->credentialsPath)) {
            Log::warning('Google Play credentials not configured or unreadable; skipping Android version sync.');
            return null;
        }

        $client = new GoogleClient();
        $client->setAuthConfig($this->credentialsPath);
        $client->addScope(AndroidPublisher::ANDROIDPUBLISHER);

        $service = new AndroidPublisher($client);
        $edit = $service->edits->insert($packageName, new AppEdit());
        $editId = $edit->getId();

        try {
            $track = $service->edits_tracks->get($packageName, $editId, 'production');
            $versionCode = $this->highestCompletedVersionCode($track->getReleases() ?? []);

            if ($versionCode === null) {
                return null;
            }

            return [
                'version_code' => $versionCode,
                'store_url' => "https://play.google.com/store/apps/details?id={$packageName}",
            ];
        } finally {
            $service->edits->delete($packageName, $editId);
        }
    }

    private function highestCompletedVersionCode(array $releases): ?int
    {
        $codes = [];

        foreach ($releases as $release) {
            if ($release->getStatus() !== 'completed') {
                continue;
            }
            foreach ($release->getVersionCodes() ?? [] as $code) {
                $codes[] = (int) $code;
            }
        }

        return empty($codes) ? null : max($codes);
    }
}
