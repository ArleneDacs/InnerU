# Per-Company User Tables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every company its own always-current database view (e.g. `gencys_users`, `abundance_users`) listing exactly that company's users, created/dropped automatically as companies are created/deleted, backfilled for companies that already exist — without ever touching the real `users` table.

**Architecture:** A `CompanyUserTableService` owns all the SQL (sanitizing a company's code into a safe view name, creating/dropping the per-company view, checking for name collisions, backfilling). A `CompanyObserver` wires that service into `Company` model lifecycle events (`created`, `deleted`). A migration adds the tracking column and runs the one-time backfill for existing companies. `CompanyController::store()` gets a small transaction wrapper so a failed view-creation can't leave an orphaned company row.

**Tech Stack:** Laravel 11, Eloquent model observers, raw SQL views (portable across SQLite/Postgres, same constraint as the `company_user_directory` view this builds on).

## Global Constraints

- Test suite runs on SQLite in-memory (`backend/phpunit.xml`); production runs Postgres (`backend/config/database.php` default `pgsql`). All SQL here must work identically on both — no `information_schema` on SQLite (use `sqlite_master` instead), no Postgres-only DDL syntax.
- `companies.code` is set once at creation (`CompanyController::store()`) and never modified afterward — `CompanyController::update()`'s `fillablePayload()` never includes `code`. No rename/update case needs handling.
- The generated view name always has a `_users` suffix appended after sanitization, so it can never literally equal `users` — the real `users` table cannot be name-collided by construction. The guard that matters is against colliding with *any other* existing database object (another company's view, or any other real table).
- `AppServiceProvider::boot()` (`backend/app/Providers/AppServiceProvider.php`) currently starts with `if ($this->app->runningInConsole()) { return; }`. Any new registration that must work during `php artisan migrate`, `php artisan test`, or any other console context (the observer registration does) must go **before** that line, not after.
- No Flutter/UI changes, no new API endpoints beyond the transaction wrapper already planned for `CompanyController::store()`.
- Per this project's standing convention, do not commit unless the user explicitly asks — leave changes in the working tree; confirm with the user before running any `git add`/`git commit` step below.

---

### Task 1: `CompanyUserTableService` + migration (column + backfill)

**Files:**
- Create: `backend/app/Services/CompanyUserTableService.php`
- Create: `backend/database/migrations/2026_07_27_000003_add_user_table_name_to_companies_table.php`
- Test: `backend/tests/Feature/CompanyUserTableServiceTest.php`

**Interfaces:**
- Consumes: `App\Models\Company` (`id` string UUID PK, `code` string, `user_table_name` nullable string — added by this task's migration), the existing `company_user_directory` view (columns include `company_id`, matching `Company::id`).
- Produces (for Task 2 to consume): `App\Services\CompanyUserTableService` with public methods `tableNameFor(string $code): string`, `createFor(Company $company): void`, `dropFor(Company $company): void`, `backfillAll(): void`. Task 2's `CompanyObserver` calls `createFor()` from `created()` and `dropFor()` from `deleted()`.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/Feature/CompanyUserTableServiceTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Services\CompanyUserTableService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class CompanyUserTableServiceTest extends TestCase
{
    use RefreshDatabase;

    private function insertCompanyWithoutEvents(string $code, string $name): Company
    {
        $id = (string) Str::uuid();

        DB::table('companies')->insert([
            'id' => $id,
            'name' => $name,
            'code' => $code,
            'is_active' => true,
            'theme_enabled' => false,
            'theme_is_dark' => false,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return Company::query()->findOrFail($id);
    }

    public function test_table_name_for_sanitizes_messy_input(): void
    {
        $service = app(CompanyUserTableService::class);

        $this->assertSame('gen_cys_1_users', $service->tableNameFor('Gen-Cys 1!'));
    }

    public function test_table_name_for_prefixes_a_digit_leading_result(): void
    {
        $service = app(CompanyUserTableService::class);

        $this->assertSame('c_3m_users', $service->tableNameFor('3M'));
    }

    public function test_table_name_for_falls_back_when_nothing_survives_sanitizing(): void
    {
        $service = app(CompanyUserTableService::class);

        $this->assertSame('company_users', $service->tableNameFor('!!!'));
    }

    public function test_create_for_creates_a_scoped_view_and_records_the_table_name(): void
    {
        $company = $this->insertCompanyWithoutEvents('GENCYS', 'Gencys');
        $other = $this->insertCompanyWithoutEvents('ABUNDANCE', 'Abundance');

        $user = \App\Models\User::factory()->create([
            'name' => 'Gencys Member',
            'company_id' => $company->id,
        ]);
        \App\Models\User::factory()->create([
            'name' => 'Abundance Member',
            'company_id' => $other->id,
        ]);

        app(CompanyUserTableService::class)->createFor($company);

        $company->refresh();
        $this->assertSame('gencys_users', $company->user_table_name);

        $rows = DB::table('gencys_users')->get();
        $this->assertCount(1, $rows);
        $this->assertSame('Gencys Member', $rows->first()->name);
    }

    public function test_create_for_throws_and_leaves_users_table_untouched_when_name_collides(): void
    {
        $companyA = $this->insertCompanyWithoutEvents('DUP', 'Dup One');
        $companyB = $this->insertCompanyWithoutEvents('DUP-1', 'Dup Two');

        // Force a genuine collision: create a real view under the exact name
        // companyB's code would sanitize to, before companyB gets a chance to.
        $service = app(CompanyUserTableService::class);
        $targetName = $service->tableNameFor($companyB->code);
        DB::statement("CREATE VIEW {$targetName} AS SELECT * FROM company_user_directory WHERE company_id = '{$companyA->id}'");

        $usersCountBefore = DB::table('users')->count();

        $this->expectException(\RuntimeException::class);

        try {
            $service->createFor($companyB);
        } finally {
            $this->assertSame($usersCountBefore, DB::table('users')->count());
            $companyB->refresh();
            $this->assertNull($companyB->user_table_name);
        }
    }

    public function test_drop_for_removes_the_view(): void
    {
        $company = $this->insertCompanyWithoutEvents('GENCYS', 'Gencys');
        app(CompanyUserTableService::class)->createFor($company);
        $company->refresh();

        app(CompanyUserTableService::class)->dropFor($company);

        $this->expectException(\Illuminate\Database\QueryException::class);
        DB::table('gencys_users')->get();
    }

    public function test_drop_for_is_a_noop_when_no_table_was_recorded(): void
    {
        $company = $this->insertCompanyWithoutEvents('GENCYS', 'Gencys');

        app(CompanyUserTableService::class)->dropFor($company);

        $this->assertNull($company->user_table_name);
    }

    public function test_backfill_all_creates_tables_for_companies_that_predate_it(): void
    {
        $company = $this->insertCompanyWithoutEvents('GENCYS', 'Gencys');
        \App\Models\User::factory()->create([
            'name' => 'Backfilled Member',
            'company_id' => $company->id,
        ]);

        app(CompanyUserTableService::class)->backfillAll();

        $company->refresh();
        $this->assertSame('gencys_users', $company->user_table_name);
        $rows = DB::table('gencys_users')->get();
        $this->assertCount(1, $rows);
        $this->assertSame('Backfilled Member', $rows->first()->name);
    }
}
```

Note: the migration referenced in Step 3 must run before this test file's `RefreshDatabase` migrations complete — that's automatic, since it's a normal migration file in `database/migrations/`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && php artisan test --filter=CompanyUserTableServiceTest`
Expected: FAIL — `CompanyUserTableService` doesn't exist yet, and/or `companies.user_table_name` column doesn't exist. This confirms the test exercises real, not-yet-built behavior.

- [ ] **Step 3: Write the migration**

Create `backend/database/migrations/2026_07_27_000003_add_user_table_name_to_companies_table.php`:

```php
<?php

use App\Models\Company;
use App\Services\CompanyUserTableService;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('companies', function (Blueprint $table): void {
            $table->string('user_table_name', 68)->nullable()->unique()->after('code');
        });

        app(CompanyUserTableService::class)->backfillAll();
    }

    public function down(): void
    {
        foreach (Company::query()->whereNotNull('user_table_name')->get() as $company) {
            app(CompanyUserTableService::class)->dropFor($company);
        }

        Schema::table('companies', function (Blueprint $table): void {
            $table->dropColumn('user_table_name');
        });
    }
};
```

- [ ] **Step 4: Write `CompanyUserTableService`**

Create `backend/app/Services/CompanyUserTableService.php`:

```php
<?php

namespace App\Services;

use App\Models\Company;
use Illuminate\Support\Facades\DB;

class CompanyUserTableService
{
    public function tableNameFor(string $code): string
    {
        return $this->sanitizeIdentifier($code).'_users';
    }

    public function createFor(Company $company): void
    {
        $tableName = $this->tableNameFor($company->code);

        if ($this->objectExists($tableName)) {
            throw new \RuntimeException(
                "Cannot create per-company table \"{$tableName}\" for company {$company->id}: a database object with that name already exists."
            );
        }

        if (! preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $company->id)) {
            throw new \RuntimeException("Company id \"{$company->id}\" is not a UUID; refusing to embed it in a view definition.");
        }

        DB::statement("CREATE VIEW {$tableName} AS SELECT * FROM company_user_directory WHERE company_id = '{$company->id}'");

        $company->forceFill(['user_table_name' => $tableName])->save();
    }

    public function dropFor(Company $company): void
    {
        $tableName = $company->user_table_name;

        if ($tableName === null || $tableName === '') {
            return;
        }

        if (! preg_match('/^[a-z_][a-z0-9_]*$/', $tableName)) {
            throw new \RuntimeException("Refusing to drop suspicious table name \"{$tableName}\".");
        }

        DB::statement("DROP VIEW IF EXISTS {$tableName}");
    }

    public function backfillAll(): void
    {
        Company::query()
            ->whereNull('user_table_name')
            ->orderBy('id')
            ->each(function (Company $company): void {
                $this->createFor($company);
            });
    }

    private function sanitizeIdentifier(string $code): string
    {
        $slug = strtolower(trim($code));
        $slug = preg_replace('/[^a-z0-9]+/', '_', $slug);
        $slug = trim($slug, '_');

        if ($slug === '') {
            $slug = 'company';
        }

        if (preg_match('/^[0-9]/', $slug)) {
            $slug = 'c_'.$slug;
        }

        $slug = substr($slug, 0, 50);
        $slug = rtrim($slug, '_');

        if ($slug === '') {
            $slug = 'company';
        }

        return $slug;
    }

    private function objectExists(string $name): bool
    {
        $driver = DB::connection()->getDriverName();

        if ($driver === 'sqlite') {
            $result = DB::selectOne(
                "SELECT 1 AS found FROM sqlite_master WHERE type IN ('table', 'view') AND name = ?",
                [$name]
            );

            return $result !== null;
        }

        $result = DB::selectOne(
            'SELECT 1 AS found FROM information_schema.tables WHERE table_name = ?',
            [$name]
        );

        return $result !== null;
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && php artisan test --filter=CompanyUserTableServiceTest`
Expected: PASS (8 tests).

- [ ] **Step 6: Run the full backend test suite to confirm no regressions**

Run: `cd backend && php artisan test`
Expected: PASS — same or higher total test/assertion count than the pre-task baseline (90 passed / 442 assertions), zero failures.

- [ ] **Step 7: Commit**

Only run this step if the user has explicitly approved a commit for this task. If approved:

```bash
git add backend/app/Services/CompanyUserTableService.php backend/database/migrations/2026_07_27_000003_add_user_table_name_to_companies_table.php backend/tests/Feature/CompanyUserTableServiceTest.php
git commit -m "feat: add CompanyUserTableService with per-company view create/drop/backfill"
```

---

### Task 2: Wire it up live — observer, provider registration, controller transaction

**Files:**
- Create: `backend/app/Observers/CompanyObserver.php`
- Modify: `backend/app/Providers/AppServiceProvider.php`
- Modify: `backend/app/Http/Controllers/Api/CompanyController.php:57-91` (the `store()` method)
- Test: `backend/tests/Feature/CompanyLifecycleUserTableTest.php`

**Interfaces:**
- Consumes: `App\Services\CompanyUserTableService::createFor()` / `::dropFor()` (from Task 1 — already implemented and tested in isolation there; this task proves they fire automatically through real `Company` model lifecycle events, not through direct service calls).
- Produces: nothing further downstream — this is the last task.

- [ ] **Step 1: Write the failing test**

Create `backend/tests/Feature/CompanyLifecycleUserTableTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyLifecycleUserTableTest extends TestCase
{
    use RefreshDatabase;

    public function test_creating_a_company_via_the_api_creates_its_user_table_automatically(): void
    {
        $admin = User::factory()->create(['role' => 'admin', 'is_admin' => true]);
        Sanctum::actingAs($admin);

        $response = $this->postJson('/api/companies', ['name' => 'Gencys']);

        $response->assertCreated();
        $code = $response->json('company.code');
        $this->assertIsString($code);

        $company = Company::query()->where('code', $code)->firstOrFail();
        $this->assertNotNull($company->user_table_name);

        $this->assertTrue(
            DB::table('users')->count() >= 1,
            'the real users table must still exist and be queryable after a company is created'
        );

        $rows = DB::table($company->user_table_name)->get();
        $this->assertCount(0, $rows); // no members assigned yet, but the table exists and is queryable
    }

    public function test_deleting_a_company_drops_its_user_table(): void
    {
        $admin = User::factory()->create(['role' => 'admin', 'is_admin' => true]);
        Sanctum::actingAs($admin);

        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Temp Co',
            'code' => 'TEMPCO',
        ]);
        $tableName = $company->fresh()->user_table_name;
        $this->assertNotNull($tableName);
        $this->assertNotEmpty(DB::select("SELECT 1 FROM {$tableName} LIMIT 0"));

        $this->deleteJson("/api/companies/{$company->id}")->assertOk();

        $this->expectException(\Illuminate\Database\QueryException::class);
        DB::table($tableName)->get();
    }

    public function test_a_failed_company_creation_does_not_leave_an_orphaned_row(): void
    {
        // Pre-create a real object occupying the exact name the next company's
        // code would need, forcing CompanyUserTableService::createFor() to throw.
        DB::statement('CREATE VIEW forced_collision_users AS SELECT 1 AS placeholder');

        $companiesBefore = Company::query()->count();

        try {
            Company::create([
                'id' => (string) Str::uuid(),
                'name' => 'Forced Collision',
                'code' => 'FORCED-COLLISION',
            ]);
            $this->fail('Expected createFor() to throw on name collision.');
        } catch (\RuntimeException) {
            // expected
        }

        $this->assertSame($companiesBefore, Company::query()->count());
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && php artisan test --filter=CompanyLifecycleUserTableTest`
Expected: FAIL — creating/deleting a company does not yet create/drop a per-company view (no observer wired up yet), and `Company::create()` is not yet wrapped in a transaction so the third test's assertion about no orphaned row will fail.

- [ ] **Step 3: Write the observer**

Create `backend/app/Observers/CompanyObserver.php`:

```php
<?php

namespace App\Observers;

use App\Models\Company;
use App\Services\CompanyUserTableService;

class CompanyObserver
{
    public function __construct(private readonly CompanyUserTableService $companyUserTableService)
    {
    }

    public function created(Company $company): void
    {
        $this->companyUserTableService->createFor($company);
    }

    public function deleted(Company $company): void
    {
        $this->companyUserTableService->dropFor($company);
    }
}
```

- [ ] **Step 4: Register the observer in `AppServiceProvider`**

Modify `backend/app/Providers/AppServiceProvider.php`. Add imports and register the observer as the *first* line of `boot()`, before the existing `runningInConsole()` early return (this must run in console contexts too — migrations and tests both count):

```php
<?php

namespace App\Providers;

use App\Models\Company;
use App\Observers\CompanyObserver;
use App\Services\FirebaseScryptVerifier;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\Schema;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->singleton(FirebaseScryptVerifier::class, function () {
            return new FirebaseScryptVerifier(
                config('services.firebase_scrypt.node_verifier_path'),
                config('services.firebase_scrypt.hash_config_path'),
            );
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        Company::observe(CompanyObserver::class);

        if ($this->app->runningInConsole()) {
            return;
        }

        try {
            if (! Schema::hasTable('pending_registrations')) {
                Schema::create('pending_registrations', function (Blueprint $table): void {
                    $table->id();
                    $table->string('name');
                    $table->string('email')->unique();
                    $table->string('apple_user_id')->nullable()->unique();
                    $table->text('encrypted_password');
                    $table->string('number', 30)->nullable();
                    $table->string('role', 30);
                    $table->boolean('is_coach')->default(false);
                    $table->string('company_code', 60)->nullable();
                    $table->string('company_name', 120)->nullable();
                    $table->boolean('has_company')->default(false);
                    $table->string('company_id', 60)->nullable();
                    $table->string('active_company_id', 60)->nullable();
                    $table->string('active_company_code', 60)->nullable();
                    $table->string('active_company_name', 120)->nullable();
                    $table->string('active_company_score_mode', 30)->nullable();
                    $table->string('score_mode', 30)->nullable();
                    $table->json('company_memberships')->nullable();
                    $table->json('company_ids')->nullable();
                    $table->json('company_codes')->nullable();
                    $table->unsignedInteger('daily_step_goal')->nullable();
                    $table->json('daily_tracker_items')->nullable();
                    $table->date('birthdate')->nullable();
                    $table->string('profile_pic')->nullable();
                    $table->timestamps();
                });
            }
        } catch (\Throwable) {
            // If the database is unavailable, let the request fail naturally.
        }
    }
}
```

- [ ] **Step 5: Wrap `CompanyController::store()`'s creation in a transaction**

Modify `backend/app/Http/Controllers/Api/CompanyController.php`. Replace the `store()` method body (currently lines 57-91) with:

```php
    public function store(Request $request): JsonResponse
    {
        if (! $this->isAdmin($request->user())) {
            return response()->json([
                'message' => 'Unauthorized.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:120'],
        ]);

        $name = trim((string) $validated['name']);
        $code = $this->generateUniqueCode($name);

        $company = DB::transaction(function () use ($name, $code): Company {
            return Company::create([
                'id' => (string) Str::uuid(),
                'name' => $name,
                'code' => $code,
                'is_active' => true,
                'theme_enabled' => false,
                'theme_source' => null,
                'tagline' => null,
                'theme_primary_color' => null,
                'theme_accent_color' => null,
                'theme_background_color' => null,
                'theme_surface_color' => null,
                'theme_ink_color' => null,
                'theme_muted_ink_color' => null,
                'theme_icon_color' => null,
                'theme_mode' => null,
                'theme_is_dark' => false,
            ]);
        });

        return response()->json([
            'company' => $this->payload($company),
        ], Response::HTTP_CREATED);
    }
```

`DB` and `Company` are already imported at the top of this file — no new `use` statements needed.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd backend && php artisan test --filter=CompanyLifecycleUserTableTest`
Expected: PASS (3 tests).

- [ ] **Step 7: Run the full backend test suite to confirm no regressions**

Run: `cd backend && php artisan test`
Expected: PASS — total should now include Task 1's 8 new tests plus this task's 3 (baseline 90 + 8 + 3 = 101 passed), zero failures.

- [ ] **Step 8: Commit**

Only run this step if the user has explicitly approved a commit for this task. If approved:

```bash
git add backend/app/Observers/CompanyObserver.php backend/app/Providers/AppServiceProvider.php backend/app/Http/Controllers/Api/CompanyController.php backend/tests/Feature/CompanyLifecycleUserTableTest.php
git commit -m "feat: auto-create/drop per-company user tables on company create/delete"
```

---

## Post-plan verification

After both tasks land and this deploys, confirm against real production data:

```sql
SELECT code, user_table_name FROM companies ORDER BY name;
SELECT count(*) FROM gencys_users;
SELECT count(*) FROM abundance_users;
```

This is a manual sanity check, not an automated step — the Feature tests above are what prove correctness.
