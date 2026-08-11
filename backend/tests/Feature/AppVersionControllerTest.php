<?php

namespace Tests\Feature;

use App\Models\AppVersion;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AppVersionControllerTest extends TestCase
{
    use RefreshDatabase;

    public function test_app_version_endpoint_is_reachable_without_authentication(): void
    {
        $response = $this->getJson('/api/app-version');

        $response->assertOk();
    }

    public function test_app_version_endpoint_returns_the_documented_shape(): void
    {
        AppVersion::current()->update([
            'ios_latest_version' => '1.2.0',
            'ios_store_url' => 'https://apps.apple.com/app/id123456789',
            'ios_update_required' => false,
            'android_latest_version_code' => 40,
            'android_store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            'android_update_required' => true,
        ]);

        $response = $this->getJson('/api/app-version');

        $response->assertOk()->assertExactJson([
            'ios' => [
                'latest_version' => '1.2.0',
                'store_url' => 'https://apps.apple.com/app/id123456789',
                'is_required' => false,
            ],
            'android' => [
                'latest_version_code' => 40,
                'store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
                'is_required' => true,
            ],
        ]);
    }

    public function test_app_version_endpoint_handles_a_null_ios_store_url(): void
    {
        AppVersion::current()->update([
            'ios_latest_version' => '1.0.4',
            'ios_store_url' => null,
            'ios_update_required' => true,
            'android_latest_version_code' => 34,
            'android_store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            'android_update_required' => false,
        ]);

        $response = $this->getJson('/api/app-version');

        $response->assertOk()->assertExactJson([
            'ios' => [
                'latest_version' => '1.0.4',
                'store_url' => null,
                'is_required' => true,
            ],
            'android' => [
                'latest_version_code' => 34,
                'store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
                'is_required' => false,
            ],
        ]);
    }
}
