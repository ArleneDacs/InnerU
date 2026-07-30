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

        try {
            $service->createFor($companyB);
            $this->fail('Expected createFor() to throw when the target table name already exists.');
        } catch (\RuntimeException $exception) {
            // Assert on the guard's own message, not just the exception type —
            // Illuminate\Database\QueryException also extends RuntimeException,
            // so SQLite's native "already exists" error on a raw duplicate
            // CREATE VIEW would satisfy a bare RuntimeException check even with
            // no explicit guard at all. This pins the guard's actual behavior.
            $this->assertStringContainsString('a database object with that name already exists', $exception->getMessage());
        }

        $this->assertSame($usersCountBefore, DB::table('users')->count());
        $companyB->refresh();
        $this->assertNull($companyB->user_table_name);
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
