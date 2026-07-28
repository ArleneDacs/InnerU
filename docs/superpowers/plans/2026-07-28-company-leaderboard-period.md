# Company Leaderboard Period Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an admin set/edit/remove a per-company start/end date range that bounds the company leaderboard's scoring window — activity before the start date never counts, and the daily-tracker score averages over the period's fixed length rather than however many days were actually tracked.

**Architecture:** Two nullable date columns on the existing `companies` table (one period per company, no history table). The existing `PATCH /api/companies/{company}` endpoint gains three optional fields (start, end, a clear flag) using the exact same validated-array → fillablePayload → payload pattern it already uses for every other company field. `UserScoreService` — the single shared scorer behind the leaderboard, the coach mentee list, and any other consumer — checks the user's company for a configured period before falling back to today's all-time-average behavior. The existing "Manage Companies" admin screen gets one more per-card row and edit dialog, mirroring its existing `_showEditNameDialog` exactly.

**Tech Stack:** Laravel/PHP backend (Eloquent, PHPUnit/`RefreshDatabase`+`Sanctum`), Flutter/Dart frontend.

## Global Constraints

- **One period per company** — editing replaces the existing dates; no history of past periods is kept.
- **Day count is inclusive of both boundary dates** (Aug 1–Dec 31, 2026 = 153 days, confirmed exactly — not an estimate).
- **The daily-tracker average always divides by the period's full length**, never by days elapsed so far or by days actually recorded — this is intentional, confirmed explicitly, not a bug to "fix" later.
- **"Goals score" = the existing `todo_list_score`/`goalScore` concept already in `UserScoreService`** (lives on the `daily_trackers` row) — not the separate Abundance/A12 `Goal` model system.
- **The goals score is the latest value found within the period only** — never averaged like the daily-tracker score, and never looks at a record dated before the period's start.
- **Companies with no period configured (or one that was removed) are completely unaffected** — falls through to today's existing all-time-average behavior, unchanged.
- **Applies everywhere `UserScoreService` computes a score** (leaderboard, `/api/coach/mentees`, etc.) — one shared scorer, not a leaderboard-only fork.
- **No new git commits during execution** — this repo's standing rule is no `git commit` unless a human explicitly asks in the moment. Stage changes (`git add`) but do not commit; the human commits when ready.

---

### Task 1: Backend data model + admin API

**Files:**
- Create: `backend/database/migrations/2026_07_28_000002_add_leaderboard_period_to_companies_table.php`
- Modify: `backend/app/Models/Company.php`
- Modify: `backend/app/Http/Controllers/Api/CompanyController.php`
- Test: `backend/tests/Feature/CompanyLeaderboardPeriodApiTest.php`

**Interfaces:**
- Produces: `companies.leaderboard_period_start` / `companies.leaderboard_period_end` (nullable `date` columns, `Carbon`-cast on the `Company` model when accessed). `PATCH /api/companies/{company}` accepts `leaderboardPeriodStart` (string `Y-m-d`), `leaderboardPeriodEnd` (string `Y-m-d`), `clearLeaderboardPeriod` (bool). Response payload gains `leaderboardPeriodStart` / `leaderboardPeriodEnd` (ISO date strings or `null`). Task 2 (`UserScoreService`) reads `$company->leaderboard_period_start` / `leaderboard_period_end` directly as `Carbon|null`.

- [ ] **Step 1: Write the failing API test**

Create `backend/tests/Feature/CompanyLeaderboardPeriodApiTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyLeaderboardPeriodApiTest extends TestCase
{
    use RefreshDatabase;

    private function makeAdmin(): User
    {
        return User::factory()->create(['is_admin' => true]);
    }

    private function makeCompany(): Company
    {
        return Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN001',
        ]);
    }

    public function test_admin_can_set_a_leaderboard_period(): void
    {
        $admin = $this->makeAdmin();
        $company = $this->makeCompany();
        Sanctum::actingAs($admin);

        $response = $this->patchJson("/api/companies/{$company->id}", [
            'leaderboardPeriodStart' => '2026-08-01',
            'leaderboardPeriodEnd' => '2026-12-31',
        ]);

        $response->assertOk()
            ->assertJsonPath('company.leaderboardPeriodStart', '2026-08-01')
            ->assertJsonPath('company.leaderboardPeriodEnd', '2026-12-31');

        $this->assertDatabaseHas('companies', [
            'id' => $company->id,
            'leaderboard_period_start' => '2026-08-01',
            'leaderboard_period_end' => '2026-12-31',
        ]);
    }

    public function test_setting_only_the_start_date_is_rejected(): void
    {
        $admin = $this->makeAdmin();
        $company = $this->makeCompany();
        Sanctum::actingAs($admin);

        $response = $this->patchJson("/api/companies/{$company->id}", [
            'leaderboardPeriodStart' => '2026-08-01',
        ]);

        $response->assertStatus(422);
    }

    public function test_end_date_before_start_date_is_rejected(): void
    {
        $admin = $this->makeAdmin();
        $company = $this->makeCompany();
        Sanctum::actingAs($admin);

        $response = $this->patchJson("/api/companies/{$company->id}", [
            'leaderboardPeriodStart' => '2026-12-31',
            'leaderboardPeriodEnd' => '2026-08-01',
        ]);

        $response->assertStatus(422);
    }

    public function test_admin_can_remove_an_existing_period(): void
    {
        $admin = $this->makeAdmin();
        $company = $this->makeCompany();
        $company->update([
            'leaderboard_period_start' => '2026-08-01',
            'leaderboard_period_end' => '2026-12-31',
        ]);
        Sanctum::actingAs($admin);

        $response = $this->patchJson("/api/companies/{$company->id}", [
            'clearLeaderboardPeriod' => true,
        ]);

        $response->assertOk()
            ->assertJsonPath('company.leaderboardPeriodStart', null)
            ->assertJsonPath('company.leaderboardPeriodEnd', null);

        $this->assertDatabaseHas('companies', [
            'id' => $company->id,
            'leaderboard_period_start' => null,
            'leaderboard_period_end' => null,
        ]);
    }

    public function test_a_company_with_no_period_returns_null_dates(): void
    {
        $admin = $this->makeAdmin();
        $company = $this->makeCompany();
        Sanctum::actingAs($admin);

        $response = $this->getJson('/api/companies');

        $response->assertOk();
        $payload = collect($response->json('companies'))
            ->firstWhere('id', $company->id);

        $this->assertNull($payload['leaderboardPeriodStart']);
        $this->assertNull($payload['leaderboardPeriodEnd']);
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && ./vendor/bin/phpunit --filter=CompanyLeaderboardPeriodApiTest`
Expected: FAIL — column `leaderboard_period_start` doesn't exist yet (SQL error), and the two validation-rejection tests fail because there's no such validation rule yet (requests currently succeed instead of returning 422).

- [ ] **Step 3: Write the migration**

Create `backend/database/migrations/2026_07_28_000002_add_leaderboard_period_to_companies_table.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('companies', function (Blueprint $table): void {
            $table->date('leaderboard_period_start')->nullable();
            $table->date('leaderboard_period_end')->nullable();
        });
    }

    public function down(): void
    {
        Schema::table('companies', function (Blueprint $table): void {
            $table->dropColumn(['leaderboard_period_start', 'leaderboard_period_end']);
        });
    }
};
```

- [ ] **Step 4: Update the `Company` model**

In `backend/app/Models/Company.php`, add the two new columns to `$fillable` (after `'loading_video_updated_at',`):

```php
        'loading_video_updated_at',
        'leaderboard_period_start',
        'leaderboard_period_end',
    ];
```

And add both to the `casts()` array (after `'loading_video_updated_at' => 'datetime',`):

```php
            'loading_video_updated_at' => 'datetime',
            'leaderboard_period_start' => 'date',
            'leaderboard_period_end' => 'date',
        ];
    }
```

- [ ] **Step 5: Update `CompanyController::update()` validation**

In `backend/app/Http/Controllers/Api/CompanyController.php`, find this exact block inside `update()`:

```php
            'clearLoadingImage' => ['sometimes', 'boolean'],
            'clearLoadingVideo' => ['sometimes', 'boolean'],
        ]);
```

Replace it with:

```php
            'clearLoadingImage' => ['sometimes', 'boolean'],
            'clearLoadingVideo' => ['sometimes', 'boolean'],
            'leaderboardPeriodStart' => ['sometimes', 'required_with:leaderboardPeriodEnd', 'date'],
            'leaderboardPeriodEnd' => ['sometimes', 'required_with:leaderboardPeriodStart', 'date', 'after_or_equal:leaderboardPeriodStart'],
            'clearLeaderboardPeriod' => ['sometimes', 'boolean'],
        ]);
```

- [ ] **Step 6: Update `fillablePayload()` to handle the new fields**

Find this exact block:

```php
        if (array_key_exists('clearLoadingVideo', $validated) && $validated['clearLoadingVideo']) {
            $payload['loading_video_url'] = null;
            $payload['loading_video_file_name'] = null;
```

Read a few more lines below it in the actual file to find where that `if` block closes (it ends with `loading_video_updated_at = null;` then a closing brace), and add the new logic immediately after that closing brace, before the method's closing `return $payload;`:

```php
        if (array_key_exists('leaderboardPeriodStart', $validated) && array_key_exists('leaderboardPeriodEnd', $validated)) {
            $payload['leaderboard_period_start'] = $validated['leaderboardPeriodStart'];
            $payload['leaderboard_period_end'] = $validated['leaderboardPeriodEnd'];
        }
        if (array_key_exists('clearLeaderboardPeriod', $validated) && $validated['clearLeaderboardPeriod']) {
            $payload['leaderboard_period_start'] = null;
            $payload['leaderboard_period_end'] = null;
        }
```

- [ ] **Step 7: Update `payload()` to return the new fields**

Find this exact line in `payload()`:

```php
            'loadingVideoUpdatedAt' => optional($company->loading_video_updated_at)?->toIso8601String(),
            'createdAt' => optional($company->created_at)?->toIso8601String(),
```

Replace it with:

```php
            'loadingVideoUpdatedAt' => optional($company->loading_video_updated_at)?->toIso8601String(),
            'leaderboardPeriodStart' => optional($company->leaderboard_period_start)?->toDateString(),
            'leaderboardPeriodEnd' => optional($company->leaderboard_period_end)?->toDateString(),
            'createdAt' => optional($company->created_at)?->toIso8601String(),
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd backend && ./vendor/bin/phpunit --filter=CompanyLeaderboardPeriodApiTest`
Expected: `OK (5 tests, ...)`

- [ ] **Step 9: Run the full backend suite to confirm no regressions**

Run: `cd backend && ./vendor/bin/phpunit`
Expected: all tests pass, same count as before plus these 5 new ones.

- [ ] **Step 10: Stage the change (do not commit — see Global Constraints)**

```bash
git add backend/database/migrations/2026_07_28_000002_add_leaderboard_period_to_companies_table.php backend/app/Models/Company.php backend/app/Http/Controllers/Api/CompanyController.php backend/tests/Feature/CompanyLeaderboardPeriodApiTest.php
```

---

### Task 2: Period-bounded scoring in `UserScoreService`

**Files:**
- Modify: `backend/app/Services/UserScoreService.php`
- Test: `backend/tests/Feature/UserScorePeriodTest.php`

**Interfaces:**
- Consumes: `Company::$leaderboard_period_start` / `$leaderboard_period_end` (`Carbon|null`, from Task 1).
- Produces: no change to `UserScoreService`'s public method signatures (`resolveForUser`, `resolveBreakdownForUser`, `resolveForUsers`, `resolveBreakdownForUsers` all keep their existing signatures and return shapes — only their internal behavior changes when a company period is configured).

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/Feature/UserScorePeriodTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class UserScorePeriodTest extends TestCase
{
    use RefreshDatabase;

    private function makeCompanyWithPeriod(string $start, string $end): Company
    {
        return Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN001',
            'leaderboard_period_start' => $start,
            'leaderboard_period_end' => $end,
        ]);
    }

    private function makeUserInCompany(Company $company): User
    {
        return User::factory()->create([
            'company_code' => $company->code,
        ]);
    }

    public function test_a_company_with_no_period_behaves_exactly_as_before(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'NoPeriodCo',
            'code' => 'NPC001',
        ]);
        $user = $this->makeUserInCompany($company);

        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-01-01',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-01-02',
            'call' => false,
            'steps' => false,
            'exercise' => false,
            'meditation' => false,
            'learning' => false,
            'add_value' => false,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Existing behavior: sum of recorded days' scores / number of recorded days.
        // Day 1 = 100, day 2 = 0 -> average 50.
        $this->assertEquals(50.0, $breakdown['coreTaskScore']);
    }

    public function test_only_activity_within_the_period_counts(): void
    {
        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-05');
        $user = $this->makeUserInCompany($company);

        // Before the period: fully completed, high todo-list score. Must be ignored entirely.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-07-15',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 90,
            'todo_list_included_in_total' => true,
        ]);

        // Within the period: fully completed, todo-list score 50.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-03',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 50,
            'todo_list_included_in_total' => true,
        ]);

        // After the period: must also be ignored.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-10',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 99,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Period is Aug 1-5 inclusive = 5 days. Only Aug 3 counts, at 100% completion.
        // coreTaskScore = 100 / 5 = 20.
        $this->assertEquals(20.0, $breakdown['coreTaskScore']);
        // goalScore = the one in-period record's todo_list_score (50), not 90 or 99.
        $this->assertEquals(50.0, $breakdown['goalScore']);
        $this->assertEquals(35.0, $breakdown['overallScore']);
    }

    public function test_the_divisor_is_the_full_period_length_not_the_recorded_day_count(): void
    {
        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-10');
        $user = $this->makeUserInCompany($company);

        // Only 2 of the 10 period days have any record, both 100% complete.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-02',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-04',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Period Aug 1-10 inclusive = 10 days. Two 100% days sum to 200.
        // 200 / 10 = 20 -- NOT 200 / 2 = 100 (which is what today's
        // all-time-average logic would produce for the same 2 records).
        $this->assertEquals(20.0, $breakdown['coreTaskScore']);
    }

    public function test_goal_score_is_the_latest_within_period_record_not_averaged(): void
    {
        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-31');
        $user = $this->makeUserInCompany($company);

        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-05',
            'todo_list_score' => 80,
            'todo_list_included_in_total' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-20',
            'todo_list_score' => 30,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Latest record by date is Aug 20 (score 30) -- must not be
        // averaged with Aug 5's 80.
        $this->assertEquals(30.0, $breakdown['goalScore']);
    }

    public function test_a_company_with_a_period_and_zero_records_in_it_scores_zero(): void
    {
        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-31');
        $user = $this->makeUserInCompany($company);

        // Old data exists, but entirely before the period.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-01-01',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 90,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        $this->assertEquals(0.0, $breakdown['coreTaskScore']);
        $this->assertEquals(0.0, $breakdown['goalScore']);
        $this->assertEquals(0.0, $breakdown['overallScore']);
    }

    public function test_batch_resolution_applies_period_scoring_too(): void
    {
        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-10');
        $userInPeriod = $this->makeUserInCompany($company);
        $otherCompany = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'NoPeriodCo2',
            'code' => 'NPC002',
        ]);
        $userWithoutPeriod = $this->makeUserInCompany($otherCompany);

        DailyTracker::create([
            'user_id' => (string) $userInPeriod->id,
            'username' => $userInPeriod->name,
            'date' => '2026-08-02',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $userWithoutPeriod->id,
            'username' => $userWithoutPeriod->name,
            'date' => '2026-08-02',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);

        $breakdowns = app(UserScoreService::class)->resolveBreakdownForUsers(
            collect([$userInPeriod->fresh(), $userWithoutPeriod->fresh()])
        );

        // In-period user: 100 / 10-day period = 10.
        $this->assertEquals(10.0, $breakdowns[(string) $userInPeriod->id]['coreTaskScore']);
        // No-period user: unchanged all-time-average behavior, 1 recorded
        // day at 100% -> 100.
        $this->assertEquals(100.0, $breakdowns[(string) $userWithoutPeriod->id]['coreTaskScore']);
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && ./vendor/bin/phpunit --filter=UserScorePeriodTest`
Expected: `test_a_company_with_no_period_behaves_exactly_as_before` and `test_batch_resolution_applies_period_scoring_too`'s no-period assertion may already pass (that's the pre-existing behavior); every period-specific test should FAIL, since nothing reads `leaderboard_period_start`/`leaderboard_period_end` yet — all period-configured users will fall through to today's unbounded average instead.

- [ ] **Step 3: Add `Carbon` and `Company` imports**

In `backend/app/Services/UserScoreService.php`, find:

```php
use App\Models\DailyTracker;
use App\Models\User;
use App\Models\UserPoint;
use Illuminate\Support\Collection;
```

Replace with:

```php
use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\User;
use App\Models\UserPoint;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
```

- [ ] **Step 4: Add company resolution and period-bounded scoring helpers**

Find this exact block (the end of the class, right before its closing brace):

```php
    private function dailyTrackerTaskCompleted(DailyTracker $tracker, string $taskId): bool
    {
        $customDailyTasks = $tracker->custom_daily_tasks;
        if (is_array($customDailyTasks) && isset($customDailyTasks[$taskId])) {
            $customTask = $customDailyTasks[$taskId];
            if (is_array($customTask)) {
                return ($customTask['completed'] ?? false) === true;
            }

            if (is_bool($customTask)) {
                return $customTask;
            }
        }

        $column = match ($taskId) {
            'addValue' => 'add_value',
            default => $taskId,
        };

        return (bool) $tracker->{$column};
    }
}
```

Replace it with:

```php
    private function dailyTrackerTaskCompleted(DailyTracker $tracker, string $taskId): bool
    {
        $customDailyTasks = $tracker->custom_daily_tasks;
        if (is_array($customDailyTasks) && isset($customDailyTasks[$taskId])) {
            $customTask = $customDailyTasks[$taskId];
            if (is_array($customTask)) {
                return ($customTask['completed'] ?? false) === true;
            }

            if (is_bool($customTask)) {
                return $customTask;
            }
        }

        $column = match ($taskId) {
            'addValue' => 'add_value',
            default => $taskId,
        };

        return (bool) $tracker->{$column};
    }

    private function activeCompanyValue(?string $primary, ?string $fallback): string
    {
        $value = trim((string) ($primary ?? ''));
        if ($value !== '') {
            return $value;
        }

        return trim((string) ($fallback ?? ''));
    }

    /**
     * @param  Collection<int, Company>  $companies
     */
    private function matchCompany(User $user, Collection $companies): ?Company
    {
        $companyId = $this->activeCompanyValue($user->active_company_id, $user->company_id);
        $companyCode = $this->activeCompanyValue($user->active_company_code, $user->company_code);
        $companyName = $this->activeCompanyValue($user->active_company_name, $user->company_name);

        return $companies->first(function (Company $company) use ($companyId, $companyCode, $companyName): bool {
            return ($companyId !== '' && (string) $company->id === $companyId)
                || ($companyCode !== '' && (string) $company->code === $companyCode)
                || ($companyName !== '' && (string) $company->name === $companyName);
        });
    }

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, Company>
     */
    private function resolveCompaniesForUsers(Collection $users): array
    {
        $ids = [];
        $codes = [];
        $names = [];

        foreach ($users as $user) {
            $ids[] = $this->activeCompanyValue($user->active_company_id, $user->company_id);
            $codes[] = $this->activeCompanyValue($user->active_company_code, $user->company_code);
            $names[] = $this->activeCompanyValue($user->active_company_name, $user->company_name);
        }

        $ids = array_values(array_unique(array_filter($ids)));
        $codes = array_values(array_unique(array_filter($codes)));
        $names = array_values(array_unique(array_filter($names)));

        if ($ids === [] && $codes === [] && $names === []) {
            return [];
        }

        $companies = Company::query()
            ->where(function ($builder) use ($ids, $codes, $names): void {
                if ($ids !== []) {
                    $builder->orWhereIn('id', $ids);
                }
                if ($codes !== []) {
                    $builder->orWhereIn('code', $codes);
                }
                if ($names !== []) {
                    $builder->orWhereIn('name', $names);
                }
            })
            ->get();

        $result = [];
        foreach ($users as $user) {
            $company = $this->matchCompany($user, $companies);
            if ($company !== null) {
                $result[(string) $user->id] = $company;
            }
        }

        return $result;
    }

    private function hasConfiguredPeriod(?Company $company): bool
    {
        return $company !== null
            && $company->leaderboard_period_start !== null
            && $company->leaderboard_period_end !== null;
    }

    /**
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    private function scoreBreakdownForPeriod(User $user, Carbon $start, Carbon $end): array
    {
        $trackers = DailyTracker::query()
            ->where('user_id', $user->id)
            ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
            ->orderBy('date')
            ->get();

        $totalDays = $start->diffInDays($end) + 1;

        $coreTaskScoreSum = 0.0;
        $latestGoalScore = 0.0;

        foreach ($trackers as $tracker) {
            $breakdown = $this->scoreBreakdownFromDailyTracker($user, $tracker);
            $coreTaskScoreSum += $breakdown['coreTaskScore'];
            // $trackers is ordered by date ascending, so the last
            // iteration holds the latest in-period record.
            $latestGoalScore = $breakdown['goalScore'];
        }

        $coreTaskScore = $totalDays > 0 ? ($coreTaskScoreSum / $totalDays) : 0.0;
        $overallScore = ($coreTaskScore + $latestGoalScore) / 2;

        return [
            'goalScore' => $latestGoalScore,
            'coreTaskScore' => $coreTaskScore,
            'overallScore' => $overallScore,
        ];
    }
}
```

- [ ] **Step 5: Wire the period check into `resolveBreakdownForUser`**

Find this exact block near the top of the class:

```php
    /**
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    public function resolveBreakdownForUser(User $user): array
    {
        $trackers = DailyTracker::query()
```

Replace it with:

```php
    /**
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    public function resolveBreakdownForUser(User $user): array
    {
        $company = $this->resolveCompaniesForUsers(collect([$user]))[(string) $user->id] ?? null;
        if ($this->hasConfiguredPeriod($company)) {
            return $this->scoreBreakdownForPeriod(
                $user,
                $company->leaderboard_period_start,
                $company->leaderboard_period_end,
            );
        }

        $trackers = DailyTracker::query()
```

- [ ] **Step 6: Wire the period check into `resolveBreakdownForUsers`**

Find this exact block:

```php
    /**
     * @param  Collection<int, User>  $users
     * @return array<string, array{goalScore:float, coreTaskScore:float, overallScore:float}>
     */
    public function resolveBreakdownForUsers(Collection $users): array
    {
        $userIds = $users
            ->pluck('id')
            ->map(static fn ($id) => (string) $id)
            ->filter()
            ->values()
            ->all();

        if ($userIds === []) {
            return [];
        }

        $trackerScores = $this->allTrackersByUserId(
```

Replace it with:

```php
    /**
     * @param  Collection<int, User>  $users
     * @return array<string, array{goalScore:float, coreTaskScore:float, overallScore:float}>
     */
    public function resolveBreakdownForUsers(Collection $users): array
    {
        $userIds = $users
            ->pluck('id')
            ->map(static fn ($id) => (string) $id)
            ->filter()
            ->values()
            ->all();

        if ($userIds === []) {
            return [];
        }

        $companiesByUser = $this->resolveCompaniesForUsers($users);

        $scores = [];
        $periodUserIds = [];

        foreach ($users as $user) {
            $userId = (string) $user->id;
            $company = $companiesByUser[$userId] ?? null;

            if ($this->hasConfiguredPeriod($company)) {
                $scores[$userId] = $this->scoreBreakdownForPeriod(
                    $user,
                    $company->leaderboard_period_start,
                    $company->leaderboard_period_end,
                );
                $periodUserIds[] = $userId;
            }
        }

        $remainingUsers = $users->reject(
            fn (User $user) => in_array((string) $user->id, $periodUserIds, true)
        );

        if ($remainingUsers->isEmpty()) {
            return $scores;
        }

        $remainingUserIds = $remainingUsers
            ->pluck('id')
            ->map(static fn ($id) => (string) $id)
            ->values()
            ->all();

        $trackerScores = $this->allTrackersByUserId(
```

- [ ] **Step 7: Update the remainder of `resolveBreakdownForUsers` to use the remaining-users subset**

The method body after the code from Step 6 currently continues with the existing tracker/point queries and a final loop. Make these two targeted replacements within this one method.

First, find this exact block:

```php
        $trackerScores = $this->allTrackersByUserId(
            DailyTracker::query()
                ->whereIn('user_id', $userIds)
                ->orderBy('user_id')
                ->orderBy('date')
                ->orderByDesc('updated_at')
            ->get([
                    'user_id',
                    'date',
                    'step_count',
                    'step_goal',
                    'meditation',
                    'steps',
                    'call',
                    'exercise',
                    'learning',
                    'add_value',
                    'todo_list',
                    'call_count',
                    'exercise_count',
                    'exercise_minutes',
                    'learning_count',
                    'value_count',
                    'todo_list_count',
                    'todo_list_score',
                    'todo_list_score_daily_contribution',
                    'todo_list_included_in_total',
                    'user_total_score',
                    'custom_daily_tasks',
                    'meditation_minutes',
                    'company_id',
                    'company_code',
                    'company_name',
                    'updated_at',
                ])
        );

        $pointScores = $this->allPointsByUserId(
            UserPoint::query()
                ->whereIn('user_id', $userIds)
                ->orderBy('user_id')
                ->orderBy('date')
                ->orderByDesc('updated_at')
                ->get([
                    'user_id',
                    'total_points',
                    'activity_points',
                    'daily_tracker_score',
                    'todo_list_score',
                    'todo_list_score_daily_contribution',
                    'todo_list_included_in_total',
                    'user_total_score',
                    'updated_at',
                ])
        );
```

Replace it with the identical block except `$userIds` becomes `$remainingUserIds` in both `whereIn` calls:

```php
        $trackerScores = $this->allTrackersByUserId(
            DailyTracker::query()
                ->whereIn('user_id', $remainingUserIds)
                ->orderBy('user_id')
                ->orderBy('date')
                ->orderByDesc('updated_at')
            ->get([
                    'user_id',
                    'date',
                    'step_count',
                    'step_goal',
                    'meditation',
                    'steps',
                    'call',
                    'exercise',
                    'learning',
                    'add_value',
                    'todo_list',
                    'call_count',
                    'exercise_count',
                    'exercise_minutes',
                    'learning_count',
                    'value_count',
                    'todo_list_count',
                    'todo_list_score',
                    'todo_list_score_daily_contribution',
                    'todo_list_included_in_total',
                    'user_total_score',
                    'custom_daily_tasks',
                    'meditation_minutes',
                    'company_id',
                    'company_code',
                    'company_name',
                    'updated_at',
                ])
        );

        $pointScores = $this->allPointsByUserId(
            UserPoint::query()
                ->whereIn('user_id', $remainingUserIds)
                ->orderBy('user_id')
                ->orderBy('date')
                ->orderByDesc('updated_at')
                ->get([
                    'user_id',
                    'total_points',
                    'activity_points',
                    'daily_tracker_score',
                    'todo_list_score',
                    'todo_list_score_daily_contribution',
                    'todo_list_included_in_total',
                    'user_total_score',
                    'updated_at',
                ])
        );
```

Second, the final loop:

```php
        $scores = [];
        foreach ($users as $user) {
            $userId = (string) $user->id;
            if (isset($trackerScores[$userId])) {
                $scores[$userId] = $this->summarizeBreakdowns(
                    $trackerScores[$userId]
                        ->map(fn (DailyTracker $tracker) => $this->scoreBreakdownFromDailyTracker($user, $tracker))
                        ->all(),
                    $user
                );
                continue;
            }

            if (isset($pointScores[$userId])) {
                $scores[$userId] = $this->summarizeBreakdowns(
                    $pointScores[$userId]
                        ->map(fn (UserPoint $point) => $this->scoreBreakdownFromUserPoint($point))
                        ->all(),
                    $user
                );
                continue;
            }

            $score = (float) ($user->score ?? 0);
            $scores[$userId] = [
                'goalScore' => $score,
                'coreTaskScore' => 0.0,
                'overallScore' => $score,
            ];
        }

        return $scores;
    }
```

Replace it with (note: `$scores = [];` is removed since `$scores` already exists from Step 6, and the loop now iterates `$remainingUsers` instead of `$users`):

```php
        foreach ($remainingUsers as $user) {
            $userId = (string) $user->id;
            if (isset($trackerScores[$userId])) {
                $scores[$userId] = $this->summarizeBreakdowns(
                    $trackerScores[$userId]
                        ->map(fn (DailyTracker $tracker) => $this->scoreBreakdownFromDailyTracker($user, $tracker))
                        ->all(),
                    $user
                );
                continue;
            }

            if (isset($pointScores[$userId])) {
                $scores[$userId] = $this->summarizeBreakdowns(
                    $pointScores[$userId]
                        ->map(fn (UserPoint $point) => $this->scoreBreakdownFromUserPoint($point))
                        ->all(),
                    $user
                );
                continue;
            }

            $score = (float) ($user->score ?? 0);
            $scores[$userId] = [
                'goalScore' => $score,
                'coreTaskScore' => 0.0,
                'overallScore' => $score,
            ];
        }

        return $scores;
    }
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `cd backend && ./vendor/bin/phpunit --filter=UserScorePeriodTest`
Expected: `OK (6 tests, ...)`

- [ ] **Step 9: Run the full backend suite to confirm no regressions**

Run: `cd backend && ./vendor/bin/phpunit`
Expected: all tests pass (previous count + 5 from Task 1 + 6 from this task).

- [ ] **Step 10: Stage the change (do not commit — see Global Constraints)**

```bash
git add backend/app/Services/UserScoreService.php backend/tests/Feature/UserScorePeriodTest.php
```

---

### Task 3: Admin UI in Manage Companies

**Files:**
- Modify: `lib/src/services/company_api_service.dart`
- Modify: `lib/src/features/authentication/screen/adminscreen/manage_companies.dart`

**Interfaces:**
- Consumes: `PATCH /api/companies/{company}` with `leaderboardPeriodStart`/`leaderboardPeriodEnd` (`Y-m-d` strings) or `clearLeaderboardPeriod` (bool), from Task 1. Response includes `leaderboardPeriodStart`/`leaderboardPeriodEnd` (ISO date strings or `null`).
- Produces: no new files; this is the last task, no downstream consumers.

This task has no automated test — `manage_companies.dart` has no existing widget test (consistent with other admin/Firebase-network-backed screens in this codebase), so it's verified via `flutter analyze` plus a manual run-through described in the final step.

- [ ] **Step 1: Add the new fields to `CompanyApiCompany`**

In `lib/src/services/company_api_service.dart`, find:

```dart
    required this.loadingVideoUrl,
    required this.loadingVideoFileName,
  });
```

Replace with:

```dart
    required this.loadingVideoUrl,
    required this.loadingVideoFileName,
    this.leaderboardPeriodStart,
    this.leaderboardPeriodEnd,
  });
```

Find:

```dart
  final String? loadingVideoUrl;
  final String? loadingVideoFileName;

  factory CompanyApiCompany.fromJson(Map<String, dynamic> json) {
```

Replace with:

```dart
  final String? loadingVideoUrl;
  final String? loadingVideoFileName;
  final String? leaderboardPeriodStart;
  final String? leaderboardPeriodEnd;

  factory CompanyApiCompany.fromJson(Map<String, dynamic> json) {
```

Find:

```dart
      loadingVideoUrl: json['loadingVideoUrl']?.toString(),
      loadingVideoFileName: json['loadingVideoFileName']?.toString(),
    );
  }
}
```

Replace with:

```dart
      loadingVideoUrl: json['loadingVideoUrl']?.toString(),
      loadingVideoFileName: json['loadingVideoFileName']?.toString(),
      leaderboardPeriodStart: json['leaderboardPeriodStart']?.toString(),
      leaderboardPeriodEnd: json['leaderboardPeriodEnd']?.toString(),
    );
  }
}
```

- [ ] **Step 2: Run analyze on the service file**

Run: `flutter analyze lib/src/services/company_api_service.dart`
Expected: `No issues found!`

- [ ] **Step 3: Add the `intl` import and a date parser to `manage_companies.dart`**

Find the top of `lib/src/features/authentication/screen/adminscreen/manage_companies.dart`:

```dart
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:selfcare_projects/src/services/company_api_service.dart';
```

Replace with:

```dart
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:selfcare_projects/src/services/company_api_service.dart';
```

- [ ] **Step 4: Add the two new fields to `_ManagedCompany`**

Find:

```dart
class _ManagedCompany {
  const _ManagedCompany({
    required this.id,
    required this.name,
    required this.code,
    required this.themeEnabled,
    required this.logoUrl,
    required this.tagline,
    required this.themePrimaryColor,
    required this.themeAccentColor,
    required this.themeInkColor,
    required this.themeIconColor,
    required this.themeSource,
    required this.themeMode,
    required this.loadingImageUrl,
    required this.loadingVideoUrl,
  });

  factory _ManagedCompany.fromApi(CompanyApiCompany company) {
    return _ManagedCompany(
      id: company.id,
      name: company.name,
      code: company.code,
      themeEnabled: company.themeEnabled,
      logoUrl: company.logoUrl?.trim() ?? '',
      tagline: company.tagline?.trim() ?? '',
      themePrimaryColor: company.themePrimaryColor?.trim() ?? '',
      themeAccentColor: company.themeAccentColor?.trim() ?? '',
      themeInkColor: company.themeInkColor?.trim() ?? '',
      themeIconColor: company.themeIconColor?.trim() ?? '',
      themeSource: company.themeSource?.trim() ?? '',
      themeMode: company.themeMode?.trim() ?? '',
      loadingImageUrl: company.loadingImageUrl?.trim() ?? '',
      loadingVideoUrl: company.loadingVideoUrl?.trim() ?? '',
    );
  }

  final String id;
  final String name;
  final String code;
  final bool themeEnabled;
  final String logoUrl;
  final String tagline;
  final String themePrimaryColor;
  final String themeAccentColor;
  final String themeInkColor;
  final String themeIconColor;
  final String themeSource;
  final String themeMode;
  final String loadingImageUrl;
  final String loadingVideoUrl;
}
```

Replace with:

```dart
class _ManagedCompany {
  const _ManagedCompany({
    required this.id,
    required this.name,
    required this.code,
    required this.themeEnabled,
    required this.logoUrl,
    required this.tagline,
    required this.themePrimaryColor,
    required this.themeAccentColor,
    required this.themeInkColor,
    required this.themeIconColor,
    required this.themeSource,
    required this.themeMode,
    required this.loadingImageUrl,
    required this.loadingVideoUrl,
    required this.leaderboardPeriodStart,
    required this.leaderboardPeriodEnd,
  });

  factory _ManagedCompany.fromApi(CompanyApiCompany company) {
    return _ManagedCompany(
      id: company.id,
      name: company.name,
      code: company.code,
      themeEnabled: company.themeEnabled,
      logoUrl: company.logoUrl?.trim() ?? '',
      tagline: company.tagline?.trim() ?? '',
      themePrimaryColor: company.themePrimaryColor?.trim() ?? '',
      themeAccentColor: company.themeAccentColor?.trim() ?? '',
      themeInkColor: company.themeInkColor?.trim() ?? '',
      themeIconColor: company.themeIconColor?.trim() ?? '',
      themeSource: company.themeSource?.trim() ?? '',
      themeMode: company.themeMode?.trim() ?? '',
      loadingImageUrl: company.loadingImageUrl?.trim() ?? '',
      loadingVideoUrl: company.loadingVideoUrl?.trim() ?? '',
      leaderboardPeriodStart: DateTime.tryParse(
        company.leaderboardPeriodStart ?? '',
      ),
      leaderboardPeriodEnd: DateTime.tryParse(
        company.leaderboardPeriodEnd ?? '',
      ),
    );
  }

  final String id;
  final String name;
  final String code;
  final bool themeEnabled;
  final String logoUrl;
  final String tagline;
  final String themePrimaryColor;
  final String themeAccentColor;
  final String themeInkColor;
  final String themeIconColor;
  final String themeSource;
  final String themeMode;
  final String loadingImageUrl;
  final String loadingVideoUrl;
  final DateTime? leaderboardPeriodStart;
  final DateTime? leaderboardPeriodEnd;

  String get leaderboardPeriodLabel {
    final start = leaderboardPeriodStart;
    final end = leaderboardPeriodEnd;
    if (start == null || end == null) {
      return 'Leaderboard period: Not set';
    }
    final formatter = DateFormat('MMM d, yyyy');
    return 'Leaderboard period: ${formatter.format(start)} - '
        '${formatter.format(end)}';
  }
}
```

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/src/features/authentication/screen/adminscreen/manage_companies.dart`
Expected: `No issues found!`

- [ ] **Step 6: Add the `onEditLeaderboardPeriod` callback to `_CompanyManagementCard` and render the new row**

Find:

```dart
class _CompanyManagementCard extends StatelessWidget {
  const _CompanyManagementCard({
    required this.company,
    required this.isUploadingLogo,
    required this.isUploadingImage,
    required this.isUploadingVideo,
    required this.onEditName,
    required this.onCopyCode,
    required this.onEditTheme,
    required this.onThemeChanged,
    required this.onUploadLogo,
    required this.onUploadLoadingImage,
    required this.onRemoveLoadingImage,
    required this.onUploadLoadingVideo,
    required this.onRemoveLoadingVideo,
    required this.onRemoveCompany,
    required this.membersStream,
  });

  final _ManagedCompany company;
  final bool isUploadingLogo;
  final bool isUploadingImage;
  final bool isUploadingVideo;
  final VoidCallback onEditName;
  final VoidCallback onCopyCode;
  final VoidCallback onEditTheme;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onUploadLogo;
  final VoidCallback onUploadLoadingImage;
  final VoidCallback onRemoveLoadingImage;
  final VoidCallback onUploadLoadingVideo;
  final VoidCallback onRemoveLoadingVideo;
  final VoidCallback onRemoveCompany;
  final Stream<List<_CompanyMember>> membersStream;
```

Replace with:

```dart
class _CompanyManagementCard extends StatelessWidget {
  const _CompanyManagementCard({
    required this.company,
    required this.isUploadingLogo,
    required this.isUploadingImage,
    required this.isUploadingVideo,
    required this.onEditName,
    required this.onCopyCode,
    required this.onEditTheme,
    required this.onThemeChanged,
    required this.onUploadLogo,
    required this.onUploadLoadingImage,
    required this.onRemoveLoadingImage,
    required this.onUploadLoadingVideo,
    required this.onRemoveLoadingVideo,
    required this.onRemoveCompany,
    required this.onEditLeaderboardPeriod,
    required this.membersStream,
  });

  final _ManagedCompany company;
  final bool isUploadingLogo;
  final bool isUploadingImage;
  final bool isUploadingVideo;
  final VoidCallback onEditName;
  final VoidCallback onCopyCode;
  final VoidCallback onEditTheme;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onUploadLogo;
  final VoidCallback onUploadLoadingImage;
  final VoidCallback onRemoveLoadingImage;
  final VoidCallback onUploadLoadingVideo;
  final VoidCallback onRemoveLoadingVideo;
  final VoidCallback onRemoveCompany;
  final VoidCallback onEditLeaderboardPeriod;
  final Stream<List<_CompanyMember>> membersStream;
```

Now find this exact block (right after the theme-toggle switch, before the loading-image preview):

```dart
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: company.themeEnabled,
            activeThumbColor: primaryColor,
            title: const Text(
              'Enable company theme',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle:
                const Text('Controls whether users see company branding.'),
            onChanged: onThemeChanged,
          ),
          const SizedBox(height: 8),
          ClipRRect(
```

Replace with:

```dart
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: company.themeEnabled,
            activeThumbColor: primaryColor,
            title: const Text(
              'Enable company theme',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle:
                const Text('Controls whether users see company branding.'),
            onChanged: onThemeChanged,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  company.leaderboardPeriodLabel,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Edit leaderboard period',
                onPressed: onEditLeaderboardPeriod,
                icon: Icon(CupertinoIcons.calendar, color: primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
```

- [ ] **Step 7: Wire the callback at the card's call site**

Find:

```dart
              onRemoveCompany: () => _showRemoveCompanyDialog(companies[index]),
              membersStream: _companyMembersStream(companies[index]),
            ),
          );
        },
      ),
    );
  }
}
```

Replace with:

```dart
              onRemoveCompany: () => _showRemoveCompanyDialog(companies[index]),
              onEditLeaderboardPeriod: () =>
                  _showLeaderboardPeriodDialog(companies[index]),
              membersStream: _companyMembersStream(companies[index]),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 8: Add the `_showLeaderboardPeriodDialog` method**

Find the `_showEditNameDialog` method's closing (find this exact block):

```dart
  Future<void> _updateCompanyName(
    _ManagedCompany company,
    String name,
  ) async {
    await CompanyApiService.instance.updateCompany(
      company.id,
      {'name': name},
    );
  }
```

Add the new method immediately after it (before `_copyCode`):

```dart
  Future<void> _updateCompanyName(
    _ManagedCompany company,
    String name,
  ) async {
    await CompanyApiService.instance.updateCompany(
      company.id,
      {'name': name},
    );
  }

  Future<void> _showLeaderboardPeriodDialog(_ManagedCompany company) async {
    DateTime? startDate = company.leaderboardPeriodStart;
    DateTime? endDate = company.leaderboardPeriodEnd;
    var isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> pickStartDate() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: startDate ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (picked != null) {
                setDialogState(() => startDate = picked);
              }
            }

            Future<void> pickEndDate() async {
              final picked = await showDatePicker(
                context: dialogContext,
                initialDate: endDate ?? (startDate ?? DateTime.now()),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (picked != null) {
                setDialogState(() => endDate = picked);
              }
            }

            final formatter = DateFormat('MMM d, yyyy');

            return AlertDialog(
              title: const Text('Leaderboard Period'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Only activity within this date range counts toward "
                    "this company's leaderboard.",
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start date'),
                    subtitle: Text(
                      startDate == null
                          ? 'Not set'
                          : formatter.format(startDate!),
                    ),
                    trailing: const Icon(CupertinoIcons.calendar),
                    onTap: isSaving ? null : pickStartDate,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End date'),
                    subtitle: Text(
                      endDate == null ? 'Not set' : formatter.format(endDate!),
                    ),
                    trailing: const Icon(CupertinoIcons.calendar),
                    onTap: isSaving ? null : pickEndDate,
                  ),
                ],
              ),
              actions: [
                if (company.leaderboardPeriodStart != null ||
                    company.leaderboardPeriodEnd != null)
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setDialogState(() => isSaving = true);
                            try {
                              await CompanyApiService.instance.updateCompany(
                                company.id,
                                {'clearLeaderboardPeriod': true},
                              );
                              if (!dialogContext.mounted) return;
                              Navigator.pop(dialogContext);
                              _refreshCompanies();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Leaderboard period removed for '
                                    '${company.name}.',
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Failed to remove leaderboard period: $e',
                                  ),
                                ),
                              );
                              if (dialogContext.mounted) {
                                setDialogState(() => isSaving = false);
                              }
                            }
                          },
                    child: const Text('Remove period'),
                  ),
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final start = startDate;
                          final end = endDate;
                          if (start == null || end == null) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please set both a start and end date.',
                                ),
                              ),
                            );
                            return;
                          }
                          if (end.isBefore(start)) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'End date must be on or after the start date.',
                                ),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            final keyFormat = DateFormat('yyyy-MM-dd');
                            await CompanyApiService.instance.updateCompany(
                              company.id,
                              {
                                'leaderboardPeriodStart': keyFormat.format(start),
                                'leaderboardPeriodEnd': keyFormat.format(end),
                              },
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            _refreshCompanies();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Leaderboard period saved for '
                                  '${company.name}.',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Failed to save leaderboard period: $e',
                                ),
                              ),
                            );
                            if (dialogContext.mounted) {
                              setDialogState(() => isSaving = false);
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
```

- [ ] **Step 9: Run analyze**

Run: `flutter analyze lib/src/features/authentication/screen/adminscreen/manage_companies.dart`
Expected: `No issues found!`

- [ ] **Step 10: Run the full Flutter test suite to confirm no regressions**

Run: `flutter test test/unit test/widget`
Expected: all tests pass, same count as before this task (no new frontend tests in this task).

- [ ] **Step 11: Manual verification**

This screen has no automated widget test, so confirm by hand:

1. Run the app as an admin user, open Manage Companies.
2. On any company's card, confirm a "Leaderboard period: Not set" row appears with a calendar edit icon.
3. Tap it, pick a start date and an end date, tap Save. Confirm the card now shows the formatted range (e.g. "Aug 1, 2026 - Dec 31, 2026") and a success snackbar appeared.
4. Reopen the dialog, confirm a "Remove period" button now appears; tap it, confirm the card reverts to "Not set".
5. Try setting an end date before the start date; confirm the inline error message appears and no request is sent.

- [ ] **Step 12: Stage the change (do not commit — see Global Constraints)**

```bash
git add lib/src/services/company_api_service.dart lib/src/features/authentication/screen/adminscreen/manage_companies.dart
```
