<?php

namespace Tests\Feature;

use App\Contracts\GooglePlayVersionFetcher;
use App\Services\GoogleApiPlayVersionFetcher;
use Tests\TestCase;

class GooglePlayVersionFetcherBindingTest extends TestCase
{
    public function test_the_interface_resolves_to_the_google_api_implementation(): void
    {
        $this->assertInstanceOf(
            GoogleApiPlayVersionFetcher::class,
            app(GooglePlayVersionFetcher::class),
        );
    }
}
