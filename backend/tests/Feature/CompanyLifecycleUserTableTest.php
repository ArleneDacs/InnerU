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
        $this->assertIsArray(DB::select("SELECT 1 FROM {$tableName} LIMIT 0"));

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
