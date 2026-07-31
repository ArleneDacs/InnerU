# Force-Update Alert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block outdated InnerU installs with a non-dismissible "please update" dialog, where the backend automatically discovers new App Store / Play Store releases on an hourly schedule — no manual step per release.

**Architecture:** A singleton `app_versions` row on the Laravel/Postgres backend is the single source of truth the mobile app ever asks. An hourly scheduled job keeps that row current by querying Apple's public iTunes Lookup API (iOS) and the Google Play Developer API via a service-account credential (Android). Every app launch calls the existing public `GET /api/app-version` endpoint from the splash screen and compares against the installed version; if behind, it blocks with `ForceUpdateDialog` instead of navigating to login.

**Tech Stack:** Laravel 12 / PHP 8.2 / Postgres (backend), Flutter/Dart (mobile), `google/apiclient` (Android Publisher API), `package_info_plus` (installed version lookup).

## Global Constraints

- Hard block only: no dismiss button, no "Later" option, no per-release configurable force flag.
- Dialog copy is exact: title "A new version is available", body "Please update the app to continue.", single button "Update Now".
- Any failure (network error, timeout, malformed response) fails **open** — the user proceeds into the app, never gets stuck.
- iOS comparison uses a semantic version **string** (e.g. `"1.1.0"`); Android comparison uses an integer **build/version code** (e.g. `35`) — these are different comparisons by necessity, per the Google Play Developer API's actual data shape.
- Backend endpoint `GET /api/app-version` is public/unauthenticated (must be callable before login).
- The scheduled sync command registers in `routes/console.php` alongside the existing `Schedule::command('meetings:sweep-reminders')` entry — no new cron setup needed on the server.
- The manual `app:set-version` Artisan command is kept only as a fallback/testing tool, not the primary update mechanism.
- Bundle ID / package name for both platforms: `com.valenin.inneru`.
- Backend tests run via `vendor/bin/phpunit --configuration=phpunit.pgsql.xml` (NOT `php artisan test --configuration=X`, which is known broken in this project).
- Flutter tests run via `flutter test`.
- Out of scope (do not build): soft-nag/dismissible mode, admin webpage for editing the version record, rechecking on app resume, alerting on Google credential expiry.

---

## File Structure

**Backend (`backend/`):**
- `database/migrations/2026_08_01_000001_create_app_versions_table.php` — new table + seeded default row
- `app/Models/AppVersion.php` — singleton model
- `app/Http/Controllers/Api/AppVersionController.php` — public read endpoint
- `routes/api.php` — new route (modify)
- `app/Console/Commands/SetAppVersion.php` — manual override command
- `app/Contracts/GooglePlayVersionFetcher.php` — interface isolating the Google SDK boundary
- `app/Services/GoogleApiPlayVersionFetcher.php` — concrete Google Play Developer API implementation
- `app/Providers/AppServiceProvider.php` — container binding (modify)
- `config/services.php` — Google Play config block (modify)
- `.env.example` — new env entries (modify)
- `app/Services/StoreVersionSyncService.php` — orchestrates both platforms, fail-open per platform
- `app/Console/Commands/SyncStoreVersions.php` — thin scheduled command
- `routes/console.php` — scheduler registration (modify)

**Flutter (`lib/`):**
- `pubspec.yaml` — add `package_info_plus` (modify)
- `lib/src/services/app_update_service.dart` — pure comparison logic + network wrapper
- `lib/src/features/authentication/screen/splash_screen/force_update_dialog.dart` — blocking dialog widget
- `lib/src/features/authentication/screen/splash_screen/splash_screen.dart` — wire in the gated check (modify)

---

### Task 1: `app_versions` table + `AppVersion` model

**Files:**
- Create: `backend/database/migrations/2026_08_01_000001_create_app_versions_table.php`
- Create: `backend/app/Models/AppVersion.php`
- Test: `backend/tests/Feature/AppVersionModelTest.php`

**Interfaces:**
- Produces: `App\Models\AppVersion::current(): AppVersion` — always returns the same singleton row (columns: `ios_latest_version` string, `ios_store_url` nullable string, `android_latest_version_code` int, `android_store_url` nullable string).

- [ ] **Step 1: Write the failing test**

```php
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
```

Save this to `backend/tests/Feature/AppVersionModelTest.php`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=AppVersionModelTest`
Expected: FAIL — class `App\Models\AppVersion` not found.

- [ ] **Step 3: Create the migration**

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('app_versions', function (Blueprint $table): void {
            $table->id();
            $table->string('ios_latest_version', 32);
            $table->string('ios_store_url')->nullable();
            $table->unsignedInteger('android_latest_version_code');
            $table->string('android_store_url')->nullable();
            $table->timestamps();
        });

        DB::table('app_versions')->insert([
            'ios_latest_version' => '1.0.4',
            'ios_store_url' => null,
            'android_latest_version_code' => 34,
            'android_store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('app_versions');
    }
};
```

Save this to `backend/database/migrations/2026_08_01_000001_create_app_versions_table.php`.

- [ ] **Step 4: Create the model**

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AppVersion extends Model
{
    protected $table = 'app_versions';

    protected $fillable = [
        'ios_latest_version',
        'ios_store_url',
        'android_latest_version_code',
        'android_store_url',
    ];

    protected function casts(): array
    {
        return [
            'android_latest_version_code' => 'integer',
        ];
    }

    public static function current(): self
    {
        return static::query()->firstOrCreate([], [
            'ios_latest_version' => '1.0.4',
            'ios_store_url' => null,
            'android_latest_version_code' => 34,
            'android_store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
        ]);
    }
}
```

Save this to `backend/app/Models/AppVersion.php`.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=AppVersionModelTest`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add backend/database/migrations/2026_08_01_000001_create_app_versions_table.php backend/app/Models/AppVersion.php backend/tests/Feature/AppVersionModelTest.php
git commit -m "feat(backend): add app_versions singleton table and model"
```

---

### Task 2: Public `GET /api/app-version` endpoint

**Files:**
- Create: `backend/app/Http/Controllers/Api/AppVersionController.php`
- Modify: `backend/routes/api.php`
- Test: `backend/tests/Feature/AppVersionControllerTest.php`

**Interfaces:**
- Consumes: `App\Models\AppVersion::current()` (Task 1)
- Produces: `GET /api/app-version` returning `{"ios": {"latest_version": string, "store_url": string|null}, "android": {"latest_version_code": int, "store_url": string|null}}`

- [ ] **Step 1: Write the failing test**

```php
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
            'android_latest_version_code' => 40,
            'android_store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
        ]);

        $response = $this->getJson('/api/app-version');

        $response->assertOk()->assertExactJson([
            'ios' => [
                'latest_version' => '1.2.0',
                'store_url' => 'https://apps.apple.com/app/id123456789',
            ],
            'android' => [
                'latest_version_code' => 40,
                'store_url' => 'https://play.google.com/store/apps/details?id=com.valenin.inneru',
            ],
        ]);
    }
}
```

Save this to `backend/tests/Feature/AppVersionControllerTest.php`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=AppVersionControllerTest`
Expected: FAIL — route `/api/app-version` not found (404).

- [ ] **Step 3: Create the controller**

```php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AppVersion;
use Illuminate\Http\JsonResponse;

class AppVersionController extends Controller
{
    public function show(): JsonResponse
    {
        $version = AppVersion::current();

        return response()->json([
            'ios' => [
                'latest_version' => $version->ios_latest_version,
                'store_url' => $version->ios_store_url,
            ],
            'android' => [
                'latest_version_code' => $version->android_latest_version_code,
                'store_url' => $version->android_store_url,
            ],
        ]);
    }
}
```

Save this to `backend/app/Http/Controllers/Api/AppVersionController.php`.

- [ ] **Step 4: Register the route**

In `backend/routes/api.php`, add the import alongside the other controller imports at the top:

```php
use App\Http\Controllers\Api\AppVersionController;
```

Then add the route directly after the existing `/health` route:

```php
Route::get('/health', fn () => response()->json([
    'ok' => true,
    'service' => config('app.name'),
    'timestamp' => now()->toIso8601String(),
]));

Route::get('/app-version', [AppVersionController::class, 'show']);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=AppVersionControllerTest`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
git add backend/app/Http/Controllers/Api/AppVersionController.php backend/routes/api.php backend/tests/Feature/AppVersionControllerTest.php
git commit -m "feat(backend): expose public GET /api/app-version endpoint"
```

---

### Task 3: Manual override command (`app:set-version`)

**Files:**
- Create: `backend/app/Console/Commands/SetAppVersion.php`
- Test: `backend/tests/Feature/SetAppVersionCommandTest.php`

**Interfaces:**
- Consumes: `App\Models\AppVersion::current()` (Task 1)
- Produces: `php artisan app:set-version {platform} {version} {storeUrl?}` — fallback/testing tool, not the primary mechanism.

- [ ] **Step 1: Write the failing test**

```php
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
```

Save this to `backend/tests/Feature/SetAppVersionCommandTest.php`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=SetAppVersionCommandTest`
Expected: FAIL — command `app:set-version` not defined.

- [ ] **Step 3: Write the command**

```php
<?php

namespace App\Console\Commands;

use App\Models\AppVersion;
use Illuminate\Console\Command;

class SetAppVersion extends Command
{
    protected $signature = 'app:set-version {platform : "ios" or "android"} {version : version string (ios) or version code integer (android)} {storeUrl? : optional store URL override}';

    protected $description = 'Manually set the latest published version for iOS or Android (fallback to the automatic hourly sync).';

    public function handle(): int
    {
        $platform = strtolower((string) $this->argument('platform'));
        $version = (string) $this->argument('version');
        $storeUrl = $this->argument('storeUrl');

        if (! in_array($platform, ['ios', 'android'], true)) {
            $this->error('Platform must be "ios" or "android".');
            return self::FAILURE;
        }

        $appVersion = AppVersion::current();

        if ($platform === 'ios') {
            $appVersion->ios_latest_version = $version;
            if ($storeUrl !== null) {
                $appVersion->ios_store_url = $storeUrl;
            }
        } else {
            if (! ctype_digit($version)) {
                $this->error('Android version must be an integer version code, e.g. 35.');
                return self::FAILURE;
            }
            $appVersion->android_latest_version_code = (int) $version;
            if ($storeUrl !== null) {
                $appVersion->android_store_url = $storeUrl;
            }
        }

        $appVersion->save();

        $this->info("Updated {$platform} latest version to {$version}.");

        return self::SUCCESS;
    }
}
```

Save this to `backend/app/Console/Commands/SetAppVersion.php`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=SetAppVersionCommandTest`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/app/Console/Commands/SetAppVersion.php backend/tests/Feature/SetAppVersionCommandTest.php
git commit -m "feat(backend): add app:set-version manual override command"
```

---

### Task 4: Google Play fetcher interface + implementation + wiring

**Files:**
- Create: `backend/app/Contracts/GooglePlayVersionFetcher.php`
- Create: `backend/app/Services/GoogleApiPlayVersionFetcher.php`
- Modify: `backend/config/services.php`
- Modify: `backend/app/Providers/AppServiceProvider.php`
- Modify: `backend/.env.example`
- Test: `backend/tests/Feature/GooglePlayVersionFetcherBindingTest.php`

**Interfaces:**
- Produces: `App\Contracts\GooglePlayVersionFetcher::fetchLatestProductionVersionCode(string $packageName): ?array` returning `['version_code' => int, 'store_url' => string]` or `null`. This interface is what Task 5 mocks — the concrete Google SDK calls inside `GoogleApiPlayVersionFetcher` are intentionally not unit-tested here (they wrap an external SDK); the interface boundary is what makes the sync logic in Task 5 testable.

- [ ] **Step 1: Add the composer dependency**

Run: `cd backend && composer require google/apiclient`
Expected: `google/apiclient` and its dependencies (including guzzlehttp/guzzle) added to `composer.json` / `composer.lock`.

- [ ] **Step 2: Write the failing test**

```php
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
```

Save this to `backend/tests/Feature/GooglePlayVersionFetcherBindingTest.php`.

- [ ] **Step 3: Run test to verify it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=GooglePlayVersionFetcherBindingTest`
Expected: FAIL — interface/class not found.

- [ ] **Step 4: Create the interface**

```php
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
```

Save this to `backend/app/Contracts/GooglePlayVersionFetcher.php`.

- [ ] **Step 5: Create the concrete implementation**

```php
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
```

Save this to `backend/app/Services/GoogleApiPlayVersionFetcher.php`.

- [ ] **Step 6: Add config entries**

In `backend/config/services.php`, add this block after the existing `'apple' => [...]` block:

```php
    'google_play' => [
        'package_name' => env('GOOGLE_PLAY_PACKAGE_NAME', 'com.valenin.inneru'),
        'credentials_path' => env('GOOGLE_PLAY_CREDENTIALS_PATH'),
    ],
```

- [ ] **Step 7: Bind the interface in the container**

In `backend/app/Providers/AppServiceProvider.php`, add these imports at the top:

```php
use App\Contracts\GooglePlayVersionFetcher;
use App\Services\GoogleApiPlayVersionFetcher;
```

Then add this line inside the existing `register()` method, alongside the existing `FirebaseScryptVerifier` binding:

```php
        $this->app->bind(GooglePlayVersionFetcher::class, function () {
            return new GoogleApiPlayVersionFetcher(config('services.google_play.credentials_path'));
        });
```

- [ ] **Step 8: Add `.env.example` entries**

In `backend/.env.example`, add near the existing `GOOGLE_*` entries:

```
GOOGLE_PLAY_PACKAGE_NAME=com.valenin.inneru
GOOGLE_PLAY_CREDENTIALS_PATH=
```

- [ ] **Step 9: Run test to verify it passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=GooglePlayVersionFetcherBindingTest`
Expected: PASS (1 test)

- [ ] **Step 10: Commit**

```bash
git add backend/composer.json backend/composer.lock backend/app/Contracts/GooglePlayVersionFetcher.php backend/app/Services/GoogleApiPlayVersionFetcher.php backend/config/services.php backend/app/Providers/AppServiceProvider.php backend/.env.example backend/tests/Feature/GooglePlayVersionFetcherBindingTest.php
git commit -m "feat(backend): add Google Play Developer API fetcher behind an interface"
```

---

### Task 5: `StoreVersionSyncService`

**Files:**
- Create: `backend/app/Services/StoreVersionSyncService.php`
- Test: `backend/tests/Feature/StoreVersionSyncServiceTest.php`

**Interfaces:**
- Consumes: `App\Models\AppVersion::current()` (Task 1), `App\Contracts\GooglePlayVersionFetcher::fetchLatestProductionVersionCode(string): ?array` (Task 4)
- Produces: `App\Services\StoreVersionSyncService::syncAll(): void`, `::syncIosVersion(): void`, `::syncAndroidVersion(): void` — each platform's failure is caught independently and never propagates.

- [ ] **Step 1: Write the failing tests**

```php
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
        $this->assertSame(50, $version->android_latest_version_code);
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
```

Save this to `backend/tests/Feature/StoreVersionSyncServiceTest.php`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=StoreVersionSyncServiceTest`
Expected: FAIL — class `App\Services\StoreVersionSyncService` not found.

- [ ] **Step 3: Write the service**

```php
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
            Log::warning('Failed to sync iOS store version: ' . $e->getMessage());
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
            Log::warning('Failed to sync Android store version: ' . $e->getMessage());
        }
    }
}
```

Save this to `backend/app/Services/StoreVersionSyncService.php`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=StoreVersionSyncServiceTest`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add backend/app/Services/StoreVersionSyncService.php backend/tests/Feature/StoreVersionSyncServiceTest.php
git commit -m "feat(backend): add StoreVersionSyncService with per-platform fail-open sync"
```

---

### Task 6: Scheduled command (`app:sync-store-versions`)

**Files:**
- Create: `backend/app/Console/Commands/SyncStoreVersions.php`
- Modify: `backend/routes/console.php`
- Test: `backend/tests/Feature/SyncStoreVersionsCommandTest.php`

**Interfaces:**
- Consumes: `App\Services\StoreVersionSyncService::syncAll()` (Task 5)
- Produces: `php artisan app:sync-store-versions`, scheduled hourly.

- [ ] **Step 1: Write the failing test**

```php
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
```

Save this to `backend/tests/Feature/SyncStoreVersionsCommandTest.php`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=SyncStoreVersionsCommandTest`
Expected: FAIL — command `app:sync-store-versions` not defined.

- [ ] **Step 3: Write the command**

```php
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
```

Save this to `backend/app/Console/Commands/SyncStoreVersions.php`.

- [ ] **Step 4: Register the schedule**

In `backend/routes/console.php`, add this line directly after the existing `Schedule::command('meetings:sweep-reminders')->everyFifteenMinutes();` line:

```php
Schedule::command('app:sync-store-versions')->hourly();
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd backend && vendor/bin/phpunit --configuration=phpunit.pgsql.xml --filter=SyncStoreVersionsCommandTest`
Expected: PASS (1 test)

- [ ] **Step 6: Commit**

```bash
git add backend/app/Console/Commands/SyncStoreVersions.php backend/routes/console.php backend/tests/Feature/SyncStoreVersionsCommandTest.php
git commit -m "feat(backend): schedule hourly app:sync-store-versions command"
```

**Note for whoever deploys this:** the Android sync will log a warning and skip itself every run until `GOOGLE_PLAY_CREDENTIALS_PATH` is set on the server to a real service-account JSON key (see the design spec's "One-time external setup" section for the exact Google Play Console steps). iOS requires no setup and will start working immediately.

---

### Task 7: `AppUpdateService` (Flutter)

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/src/services/app_update_service.dart`
- Test: `test/unit/app_update_service_test.dart`

**Interfaces:**
- Consumes: `ApiClient.instance.getJson(String path): Future<Map<String, dynamic>>` (existing, `lib/src/services/api_client.dart`)
- Produces: `AppUpdateCheckResult` (fields: `bool isOutdated`, `String? storeUrl`; factory `AppUpdateCheckResult.outdated(String storeUrl)`; constant `AppUpdateCheckResult.upToDate`), `AppUpdateService.instance.checkForUpdate(): Future<AppUpdateCheckResult>`, `AppUpdateService.evaluate({required Map<String,dynamic> response, required bool isIOS, required String installedVersion, required String installedBuildNumber}): AppUpdateCheckResult` (static, pure).

- [ ] **Step 1: Add the `package_info_plus` dependency**

Run: `flutter pub add package_info_plus`
Expected: `pubspec.yaml` gains a `package_info_plus: ^<resolved version>` line under `dependencies:`, and `pubspec.lock` updates.

- [ ] **Step 2: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/services/app_update_service.dart';

void main() {
  group('AppUpdateService.evaluate — iOS version comparison', () {
    test('reports outdated when installed version is behind', () {
      final result = AppUpdateService.evaluate(
        response: {
          'ios': {
            'latest_version': '1.1.0',
            'store_url': 'https://apps.apple.com/app/id1',
          },
        },
        isIOS: true,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isTrue);
      expect(result.storeUrl, 'https://apps.apple.com/app/id1');
    });

    test('reports up to date when versions are equal', () {
      final result = AppUpdateService.evaluate(
        response: {
          'ios': {
            'latest_version': '1.0.4',
            'store_url': 'https://apps.apple.com/app/id1',
          },
        },
        isIOS: true,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });

    test('reports up to date when installed version is newer', () {
      final result = AppUpdateService.evaluate(
        response: {
          'ios': {
            'latest_version': '1.0.0',
            'store_url': 'https://apps.apple.com/app/id1',
          },
        },
        isIOS: true,
        installedVersion: '1.1.0',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });

    test('handles mismatched segment counts', () {
      final result = AppUpdateService.evaluate(
        response: {
          'ios': {
            'latest_version': '1.0.4.1',
            'store_url': 'https://apps.apple.com/app/id1',
          },
        },
        isIOS: true,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isTrue);
    });

    test('fails open when the ios payload is missing fields', () {
      final result = AppUpdateService.evaluate(
        response: {'ios': <String, dynamic>{}},
        isIOS: true,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });
  });

  group('AppUpdateService.evaluate — Android build number comparison', () {
    test('reports outdated when installed build number is behind', () {
      final result = AppUpdateService.evaluate(
        response: {
          'android': {
            'latest_version_code': 40,
            'store_url':
                'https://play.google.com/store/apps/details?id=com.valenin.inneru',
          },
        },
        isIOS: false,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isTrue);
    });

    test('reports up to date when build numbers match', () {
      final result = AppUpdateService.evaluate(
        response: {
          'android': {
            'latest_version_code': 34,
            'store_url':
                'https://play.google.com/store/apps/details?id=com.valenin.inneru',
          },
        },
        isIOS: false,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });

    test('fails open when installed build number is not numeric', () {
      final result = AppUpdateService.evaluate(
        response: {
          'android': {
            'latest_version_code': 40,
            'store_url':
                'https://play.google.com/store/apps/details?id=com.valenin.inneru',
          },
        },
        isIOS: false,
        installedVersion: '1.0.4',
        installedBuildNumber: 'not-a-number',
      );

      expect(result.isOutdated, isFalse);
    });

    test('fails open when the android payload is missing fields', () {
      final result = AppUpdateService.evaluate(
        response: {'android': <String, dynamic>{}},
        isIOS: false,
        installedVersion: '1.0.4',
        installedBuildNumber: '34',
      );

      expect(result.isOutdated, isFalse);
    });
  });
}
```

Save this to `test/unit/app_update_service_test.dart`.

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/unit/app_update_service_test.dart`
Expected: FAIL — `package:selfcare_projects/src/services/app_update_service.dart` not found.

- [ ] **Step 4: Write the service**

```dart
import 'dart:io' show Platform;

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:selfcare_projects/src/services/api_client.dart';

class AppUpdateCheckResult {
  const AppUpdateCheckResult._({required this.isOutdated, this.storeUrl});

  final bool isOutdated;
  final String? storeUrl;

  static const AppUpdateCheckResult upToDate =
      AppUpdateCheckResult._(isOutdated: false);

  factory AppUpdateCheckResult.outdated(String storeUrl) {
    return AppUpdateCheckResult._(isOutdated: true, storeUrl: storeUrl);
  }
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  Future<AppUpdateCheckResult> checkForUpdate() async {
    try {
      final response = await ApiClient.instance
          .getJson('/api/app-version')
          .timeout(const Duration(seconds: 5));

      final packageInfo = await PackageInfo.fromPlatform();

      return evaluate(
        response: response,
        isIOS: Platform.isIOS,
        installedVersion: packageInfo.version,
        installedBuildNumber: packageInfo.buildNumber,
      );
    } catch (error, stack) {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, fatal: false);
      return AppUpdateCheckResult.upToDate;
    }
  }

  static AppUpdateCheckResult evaluate({
    required Map<String, dynamic> response,
    required bool isIOS,
    required String installedVersion,
    required String installedBuildNumber,
  }) {
    if (isIOS) {
      final ios = response['ios'] as Map<String, dynamic>?;
      final latestVersion = ios?['latest_version'] as String?;
      final storeUrl = ios?['store_url'] as String?;

      if (latestVersion == null || storeUrl == null) {
        return AppUpdateCheckResult.upToDate;
      }

      return _isVersionBehind(installedVersion, latestVersion)
          ? AppUpdateCheckResult.outdated(storeUrl)
          : AppUpdateCheckResult.upToDate;
    }

    final android = response['android'] as Map<String, dynamic>?;
    final latestVersionCodeRaw = android?['latest_version_code'];
    final storeUrl = android?['store_url'] as String?;

    final installedCode = int.tryParse(installedBuildNumber);
    final latestCode = latestVersionCodeRaw is int
        ? latestVersionCodeRaw
        : int.tryParse(latestVersionCodeRaw?.toString() ?? '');

    if (installedCode == null || latestCode == null || storeUrl == null) {
      return AppUpdateCheckResult.upToDate;
    }

    return installedCode < latestCode
        ? AppUpdateCheckResult.outdated(storeUrl)
        : AppUpdateCheckResult.upToDate;
  }

  static bool _isVersionBehind(String installed, String latest) {
    final installedParts =
        installed.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final latestParts =
        latest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final length = installedParts.length > latestParts.length
        ? installedParts.length
        : latestParts.length;

    for (var i = 0; i < length; i++) {
      final a = i < installedParts.length ? installedParts[i] : 0;
      final b = i < latestParts.length ? latestParts[i] : 0;
      if (a != b) {
        return a < b;
      }
    }
    return false;
  }
}
```

Save this to `lib/src/services/app_update_service.dart`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/unit/app_update_service_test.dart`
Expected: PASS (9 tests)

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/src/services/app_update_service.dart test/unit/app_update_service_test.dart
git commit -m "feat(mobile): add AppUpdateService with per-platform version comparison"
```

---

### Task 8: `ForceUpdateDialog` widget

**Files:**
- Create: `lib/src/features/authentication/screen/splash_screen/force_update_dialog.dart`
- Test: `test/widget/force_update_dialog_test.dart`

**Interfaces:**
- Produces: `showForceUpdateDialog(BuildContext context, {required String storeUrl, required Future<void> Function(String storeUrl) onUpdateNow}): Future<void>` — non-dismissible, single "Update Now" button.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/force_update_dialog.dart';

void main() {
  group('ForceUpdateDialog', () {
    testWidgets('shows the required copy and a single Update Now button',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showForceUpdateDialog(
                context,
                storeUrl: 'https://apps.apple.com/app/id1',
                onUpdateNow: (_) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('A new version is available'), findsOneWidget);
      expect(find.text('Please update the app to continue.'), findsOneWidget);
      expect(find.text('Update Now'), findsOneWidget);
    });

    testWidgets('tapping Update Now invokes the callback with the store URL',
        (tester) async {
      String? tappedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showForceUpdateDialog(
                context,
                storeUrl:
                    'https://play.google.com/store/apps/details?id=com.valenin.inneru',
                onUpdateNow: (url) async => tappedUrl = url,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Update Now'));
      await tester.pumpAndSettle();

      expect(
        tappedUrl,
        'https://play.google.com/store/apps/details?id=com.valenin.inneru',
      );
    });

    testWidgets('cannot be dismissed by tapping the barrier', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showForceUpdateDialog(
                context,
                storeUrl: 'https://apps.apple.com/app/id1',
                onUpdateNow: (_) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('A new version is available'), findsOneWidget);
    });
  });
}
```

Save this to `test/widget/force_update_dialog_test.dart`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/force_update_dialog_test.dart`
Expected: FAIL — `force_update_dialog.dart` not found.

- [ ] **Step 3: Write the widget**

```dart
import 'package:flutter/material.dart';

class ForceUpdateDialog extends StatelessWidget {
  const ForceUpdateDialog({
    super.key,
    required this.storeUrl,
    required this.onUpdateNow,
  });

  final String storeUrl;
  final Future<void> Function(String storeUrl) onUpdateNow;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('A new version is available'),
        content: const Text('Please update the app to continue.'),
        actions: [
          TextButton(
            onPressed: () => onUpdateNow(storeUrl),
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }
}

Future<void> showForceUpdateDialog(
  BuildContext context, {
  required String storeUrl,
  required Future<void> Function(String storeUrl) onUpdateNow,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ForceUpdateDialog(
      storeUrl: storeUrl,
      onUpdateNow: onUpdateNow,
    ),
  );
}
```

Save this to `lib/src/features/authentication/screen/splash_screen/force_update_dialog.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/force_update_dialog_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/authentication/screen/splash_screen/force_update_dialog.dart test/widget/force_update_dialog_test.dart
git commit -m "feat(mobile): add non-dismissible ForceUpdateDialog"
```

---

### Task 9: Wire the gated check into `splash_screen.dart`

**Files:**
- Modify: `lib/src/features/authentication/screen/splash_screen/splash_screen.dart`
- Test: `test/widget/splash_screen_test.dart`

**Interfaces:**
- Consumes: `AppUpdateService.instance.checkForUpdate()` (Task 7), `AppUpdateCheckResult` (Task 7), `showForceUpdateDialog(...)` (Task 8)
- Produces: `SplashScreen({Key? key, Future<AppUpdateCheckResult> Function()? checkForUpdate, Future<void> Function(String storeUrl)? onUpdateNow})` — the two optional constructor params are the testing seam; production code omits them and gets the real service + real `url_launcher` call.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/splash_screen.dart';
import 'package:selfcare_projects/src/services/app_update_service.dart';

void main() {
  group('SplashScreen force-update gating', () {
    testWidgets(
        'shows the blocking dialog when the update check reports outdated',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          checkForUpdate: () async =>
              AppUpdateCheckResult.outdated('https://apps.apple.com/app/id1'),
          onUpdateNow: (_) async {},
        ),
      ));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.text('A new version is available'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('navigates to login when the app is up to date',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          checkForUpdate: () async => AppUpdateCheckResult.upToDate,
        ),
      ));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('A new version is available'), findsNothing);
    });

    testWidgets('navigates to login when the update check fails',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          checkForUpdate: () =>
              Future<AppUpdateCheckResult>.error('network down'),
        ),
      ));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
```

Save this to `test/widget/splash_screen_test.dart`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/widget/splash_screen_test.dart`
Expected: FAIL — `SplashScreen` has no `checkForUpdate`/`onUpdateNow` constructor parameters yet.

- [ ] **Step 3: Rewrite the splash screen**

Replace the full contents of `lib/src/features/authentication/screen/splash_screen/splash_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:selfcare_projects/src/constants/image_strings.dart';
import 'package:selfcare_projects/src/features/authentication/screen/login/login_screen.dart';
import 'package:selfcare_projects/src/features/authentication/screen/splash_screen/force_update_dialog.dart';
import 'package:selfcare_projects/src/services/app_update_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.checkForUpdate,
    this.onUpdateNow,
  });

  final Future<AppUpdateCheckResult> Function()? checkForUpdate;
  final Future<void> Function(String storeUrl)? onUpdateNow;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _runSplash();
  }

  Future<void> _runSplash() async {
    final checkForUpdate =
        widget.checkForUpdate ?? AppUpdateService.instance.checkForUpdate;

    final brandingDelay = Future<void>.delayed(const Duration(seconds: 3));
    final updateCheck = checkForUpdate().then<AppUpdateCheckResult>(
      (result) => result,
      onError: (_) => AppUpdateCheckResult.upToDate,
    );

    await brandingDelay;
    final updateResult = await updateCheck;

    if (!mounted) return;

    if (updateResult.isOutdated && updateResult.storeUrl != null) {
      await showForceUpdateDialog(
        context,
        storeUrl: updateResult.storeUrl!,
        onUpdateNow: widget.onUpdateNow ?? _launchStoreUrl,
      );
      return;
    }

    navigateToLogin();
  }

  Future<void> _launchStoreUrl(String storeUrl) async {
    final uri = Uri.parse(storeUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void navigateToLogin() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage(tSplashTopIcon),
          fit: BoxFit.cover, // Ensures full coverage
        ),
      ),
    );
  }
}
```

This drops the old `Timer`/`dispose()` pair (no longer needed — `Future.delayed` plus the `mounted` guards fully replace it) and gates navigation on both the 3-second branding delay and the update check finishing, per the design spec.

**Correction (found during Task 9 implementation):** the code above attaches the
error handler to `updateCheck` via `.then(onError:)` at the point the future is
created, not via a `try/catch` around a later `await`. An earlier draft of this
step used `final updateCheck = checkForUpdate(); ... try { await updateCheck } catch (_) {...}`
— if `checkForUpdate()` returns an already-errored future (exactly what the
Step 1 test's third case does), Dart's zone machinery reports it as an
**unhandled** async error the moment it completes, since no listener was
attached yet (the widget is still awaiting the unrelated 3-second branding
delay at that point) — the later `try/catch` never gets a chance to run. The
`.then(onError:)` form attaches the handler synchronously at creation time,
closing that window, with identical fail-open behavior and the same public
API. If reusing this pattern elsewhere, use the `.then(onError:)` form, not
the try/catch-after-a-later-await form.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/widget/splash_screen_test.dart`
Expected: PASS (3 tests)

- [ ] **Step 5: Run the full Flutter test suite to check for regressions**

Run: `flutter test`
Expected: PASS (no regressions in unrelated tests)

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/authentication/screen/splash_screen/splash_screen.dart test/widget/splash_screen_test.dart
git commit -m "feat(mobile): gate splash-screen navigation on the force-update check"
```

---

## Post-plan manual step (not automatable)

After Task 6 is deployed, the Android side of the automatic sync will keep logging a warning and skipping itself until the one-time Google Play Console + Google Cloud setup (service account, JSON key, granted read-only access) described in `docs/superpowers/specs/2026-08-01-force-update-alert-design.md` is completed and `GOOGLE_PLAY_CREDENTIALS_PATH` is set on the production server. iOS works immediately with no setup.

**Deploy-time verification checklist (added after the final whole-branch review):** both platforms fail open silently by design — a broken sync shows up only as an hourly `Log::warning`, so the only way to know either side actually works is to check by hand once, right after deploying:

1. Run `php artisan app:sync-store-versions` manually on the deploy server and inspect the log output and the `app_versions` row afterward (e.g. via `php artisan tinker` → `AppVersion::current()`).
2. **Android permission risk:** `GoogleApiPlayVersionFetcher` calls `edits->insert()` to read the production track — reading a track via the Android Publisher API only works through the transient-edit flow, so it may require a broader release-management permission than a pure read-only grant provides. If the manual run logs a `403`/permission warning instead of updating `android_latest_version_code`, go back and grant the service account additional permission (Release management, not just app-info viewing) until the manual run succeeds. Note: Google has retired Play Console's old dedicated "API access" page — a service account is now granted access by inviting its `client_email` (from the downloaded JSON key) under **Play Console → Users and permissions**, the same way you'd invite a human teammate, rather than through a separate linking page.
3. **iOS storefront risk:** `syncIosVersion()` calls Apple's iTunes Lookup API with no `country` parameter, which defaults to the **US storefront**. If InnerU is not published in the US App Store, `results` will always come back empty and `ios_latest_version`/`ios_store_url` will never populate — silently, with only an hourly log line as evidence. Confirm the manual run actually populates `ios_store_url`; if it doesn't and InnerU is published outside the US, add `'country' => '<your two-letter store code>'` to the request in `StoreVersionSyncService::syncIosVersion()`.
4. Re-run the check after any Google credential rotation or Play Console permission change, since a revoked/expired credential produces the same silent-warning failure mode.
