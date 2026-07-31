<?php

namespace Tests\Feature;

use App\Models\AppVersion;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SetAppVersionCommandTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_updates_the_ios_version(): void
    {
        $this->artisan('app:set-version', [
            'platform' => 'ios',
            'version' => '1.5.0',
            'storeUrl' => 'https://apps.apple.com/app/id999',
        ])->assertExitCode(0);

        $version = AppVersion::current();
        $this->assertSame('1.5.0', $version->ios_latest_version);
        $this->assertSame('https://apps.apple.com/app/id999', $version->ios_store_url);
    }

    public function test_it_updates_the_android_version_code(): void
    {
        $this->artisan('app:set-version', [
            'platform' => 'android',
            'version' => '40',
        ])->assertExitCode(0);

        $this->assertSame(40, AppVersion::current()->android_latest_version_code);
    }

    public function test_it_rejects_a_non_numeric_android_version(): void
    {
        $this->artisan('app:set-version', [
            'platform' => 'android',
            'version' => '1.5.0',
        ])->assertExitCode(1);
    }

    public function test_it_rejects_an_unknown_platform(): void
    {
        $this->artisan('app:set-version', [
            'platform' => 'windows',
            'version' => '1.0.0',
        ])->assertExitCode(1);
    }
}
