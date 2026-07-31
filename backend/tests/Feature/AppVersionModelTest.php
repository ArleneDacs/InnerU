<?php

namespace Tests\Feature;

use App\Models\AppVersion;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AppVersionModelTest extends TestCase
{
    use RefreshDatabase;

    public function test_current_returns_the_seeded_singleton_row(): void
    {
        $version = AppVersion::current();

        $this->assertSame('1.0.4', $version->ios_latest_version);
        $this->assertSame(34, $version->android_latest_version_code);
        $this->assertSame(
            'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            $version->android_store_url,
        );
    }

    public function test_current_always_returns_the_same_row(): void
    {
        $first = AppVersion::current();
        $first->update(['ios_latest_version' => '2.0.0']);

        $second = AppVersion::current();

        $this->assertSame($first->id, $second->id);
        $this->assertSame('2.0.0', $second->ios_latest_version);
        $this->assertSame(1, AppVersion::query()->count());
    }
}
