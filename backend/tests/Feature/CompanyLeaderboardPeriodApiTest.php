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
            'leaderboard_period_start' => '2026-08-01 00:00:00',
            'leaderboard_period_end' => '2026-12-31 00:00:00',
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

    public function test_setting_only_the_end_date_is_rejected(): void
    {
        $admin = $this->makeAdmin();
        $company = $this->makeCompany();
        Sanctum::actingAs($admin);

        $response = $this->patchJson("/api/companies/{$company->id}", [
            'leaderboardPeriodEnd' => '2026-12-31',
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
