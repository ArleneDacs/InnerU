<?php

namespace App\Contracts;

interface GooglePlayVersionFetcher
{
    /**
     * Returns ['version_code' => int, 'store_url' => string] for the current
     * completed production release, or null if none could be determined.
     */
    public function fetchLatestProductionVersionCode(string $packageName): ?array;
}
