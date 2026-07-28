# Company User Directory View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a read-only Postgres view, `company_user_directory`, that joins `users` to `companies` (plus each user's latest per-company point total), so admins can browse users grouped by company directly in any database client — no UI or API changes.

**Architecture:** A single Laravel migration creates the view with a raw `CREATE VIEW` statement in `up()` and `DROP VIEW IF EXISTS` in `down()`. The view's SQL is written to be portable across both SQLite (used by the test suite, per `phpunit.xml`'s `DB_CONNECTION=sqlite`) and Postgres (used in production), so the accompanying Feature test can actually exercise it in CI rather than being skipped.

**Tech Stack:** Laravel 11 migrations, raw SQL views, PHPUnit Feature tests with `RefreshDatabase`.

## Global Constraints

- Test suite runs on SQLite in-memory (`phpunit.xml`: `DB_CONNECTION=sqlite`, `DB_DATABASE=:memory:`); production runs Postgres (`config/database.php` default `pgsql`). The view's SQL must avoid Postgres-only syntax (no `LATERAL`, no `IS NOT DISTINCT FROM`, no `NULLS LAST`) so migrations succeed identically on both engines.
- `companies.id` is a non-incrementing string primary key (see `app/Models/Company.php`); test fixtures must set `id` explicitly, e.g. `(string) Str::uuid()`, matching the existing pattern in `tests/Feature/CompanyLookupTest.php`.
- `user_points` is a per-day, per-company log (unique on `user_id, date, company_id`), not a running total column on `users` — "current points for this user in this company" means the most recent `user_points` row scoped to that `user_id` + `company_id`.
- No Flutter/UI changes. No new API endpoint. No changes to how `users.company_id` is populated.
- Per this project's standing convention (see prior migration work), do not commit unless the user explicitly asks — this plan's steps include `git add`/`git commit` for structure, but the executing agent should confirm with the user before running them if no explicit commit approval is on record for this task.

---

### Task 1: Create the `company_user_directory` view with a portable migration and a Feature test

**Files:**
- Create: `backend/database/migrations/2026_07_27_000001_create_company_user_directory_view.php`
- Test: `backend/tests/Feature/CompanyUserDirectoryViewTest.php`

**Interfaces:**
- Consumes: `App\Models\User` (`company_id` nullable string FK-by-convention to `companies.id`), `App\Models\Company` (`id` string PK, `name`, `code`, `is_active`), `App\Models\UserPoint` (`user_id`, `date`, `company_id`, `user_total_score`, `updated_at`).
- Produces: a database view `company_user_directory` with columns `user_id, name, email, role, is_coach, is_admin, number, user_created_at, company_id, company_name, company_code, company_is_active, current_points, current_points_as_of`. No PHP model wraps this view — tests and any future consumer query it via `DB::table('company_user_directory')` or raw SQL.

- [ ] **Step 1: Write the failing Feature test**

Create `backend/tests/Feature/CompanyUserDirectoryViewTest.php`:

```php
<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\User;
use App\Models\UserPoint;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class CompanyUserDirectoryViewTest extends TestCase
{
    use RefreshDatabase;

    public function test_view_lists_a_user_with_their_company_and_latest_points(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GENCYS',
        ]);

        $user = User::factory()->create([
            'name' => 'Gencys Member',
            'company_id' => $company->id,
        ]);

        UserPoint::create([
            'user_id' => $user->id,
            'date' => '2026-07-20',
            'username' => $user->name,
            'company_id' => $company->id,
            'user_total_score' => 40,
        ]);

        UserPoint::create([
            'user_id' => $user->id,
            'date' => '2026-07-25',
            'username' => $user->name,
            'company_id' => $company->id,
            'user_total_score' => 55,
        ]);

        $row = DB::table('company_user_directory')
            ->where('user_id', $user->id)
            ->first();

        $this->assertNotNull($row);
        $this->assertSame($company->id, $row->company_id);
        $this->assertSame('Gencys', $row->company_name);
        $this->assertSame('GENCYS', $row->company_code);
        $this->assertEquals(55, $row->current_points);
        $this->assertSame('2026-07-25', $row->current_points_as_of);
    }

    public function test_view_keeps_a_second_company_separate(): void
    {
        $gencys = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GENCYS',
        ]);
        $abundance = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Abundance',
            'code' => 'ABUNDANCE',
        ]);

        User::factory()->create(['name' => 'Gencys User', 'company_id' => $gencys->id]);
        User::factory()->create(['name' => 'Abundance User', 'company_id' => $abundance->id]);

        $gencysRows = DB::table('company_user_directory')
            ->where('company_code', 'GENCYS')
            ->get();
        $abundanceRows = DB::table('company_user_directory')
            ->where('company_code', 'ABUNDANCE')
            ->get();

        $this->assertCount(1, $gencysRows);
        $this->assertSame('Gencys User', $gencysRows->first()->name);
        $this->assertCount(1, $abundanceRows);
        $this->assertSame('Abundance User', $abundanceRows->first()->name);
    }

    public function test_view_includes_a_user_with_no_company_and_no_points(): void
    {
        $user = User::factory()->create([
            'name' => 'Unassigned User',
            'company_id' => null,
        ]);

        $row = DB::table('company_user_directory')
            ->where('user_id', $user->id)
            ->first();

        $this->assertNotNull($row);
        $this->assertNull($row->company_id);
        $this->assertNull($row->company_name);
        $this->assertNull($row->company_code);
        $this->assertNull($row->current_points);
        $this->assertNull($row->current_points_as_of);
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && php artisan test --filter=CompanyUserDirectoryViewTest`
Expected: FAIL — `company_user_directory` does not exist (e.g. `SQLSTATE... no such table: company_user_directory` on SQLite, or equivalent "relation does not exist" if run against Postgres). This confirms the test exercises real behavior, not a pre-existing pass.

- [ ] **Step 3: Write the migration**

Create `backend/database/migrations/2026_07_27_000001_create_company_user_directory_view.php`:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement(<<<'SQL'
            CREATE VIEW company_user_directory AS
            SELECT
                u.id AS user_id,
                u.name AS name,
                u.email AS email,
                u.role AS role,
                u.is_coach AS is_coach,
                u.is_admin AS is_admin,
                u.number AS number,
                u.created_at AS user_created_at,
                c.id AS company_id,
                c.name AS company_name,
                c.code AS company_code,
                c.is_active AS company_is_active,
                (
                    SELECT up.user_total_score
                    FROM user_points up
                    WHERE up.user_id = u.id
                      AND (up.company_id = u.company_id OR (up.company_id IS NULL AND u.company_id IS NULL))
                    ORDER BY up.date DESC, up.updated_at DESC
                    LIMIT 1
                ) AS current_points,
                (
                    SELECT up.date
                    FROM user_points up
                    WHERE up.user_id = u.id
                      AND (up.company_id = u.company_id OR (up.company_id IS NULL AND u.company_id IS NULL))
                    ORDER BY up.date DESC, up.updated_at DESC
                    LIMIT 1
                ) AS current_points_as_of
            FROM users u
            LEFT JOIN companies c ON c.id = u.company_id
            ORDER BY (c.name IS NULL), c.name, u.name
        SQL);
    }

    public function down(): void
    {
        DB::statement('DROP VIEW IF EXISTS company_user_directory');
    }
};
```

Notes for the implementer:
- The `(c.name IS NULL), c.name` ordering trick sorts non-null company names alphabetically first, with unassigned users (`c.name IS NULL`) trailing — this works identically on SQLite and Postgres, unlike Postgres-only `NULLS LAST`.
- The two correlated scalar subqueries (rather than a `LATERAL` join) are deliberately duplicated — standard SQL, portable, and each returns at most one column so there's no ambiguity.
- `(up.company_id = u.company_id OR (up.company_id IS NULL AND u.company_id IS NULL))` is a portable stand-in for `IS NOT DISTINCT FROM`, which SQLite does not support.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd backend && php artisan test --filter=CompanyUserDirectoryViewTest`
Expected: PASS (3 tests, all assertions green).

- [ ] **Step 5: Run the full backend test suite to confirm no regressions**

Run: `cd backend && php artisan test`
Expected: PASS — same or higher total test/assertion count than the pre-existing baseline, zero failures. (If the count is lower or anything fails, stop and investigate before proceeding — do not silence or skip a failing test.)

- [ ] **Step 6: Commit**

Only run this step if the user has explicitly approved a commit for this task (per this project's standing no-commit-unless-asked convention). If approved:

```bash
git add backend/database/migrations/2026_07_27_000001_create_company_user_directory_view.php backend/tests/Feature/CompanyUserDirectoryViewTest.php
git commit -m "feat: add company_user_directory view for per-company user browsing"
```

---

## Post-plan verification

After Task 1 lands, if there's access to the production database, confirm the view deploys and returns real data once CI runs the migration:

```sql
SELECT company_name, count(*) FROM company_user_directory GROUP BY company_name ORDER BY company_name;
```

This is a manual sanity check, not an automated step — the Feature test above is what proves correctness.
