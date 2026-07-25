<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyLookupTest extends TestCase
{
    use RefreshDatabase;

    public function test_lookup_matches_a_lowercase_company_id_by_an_uppercased_request(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN0KUS',
        ]);

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->getJson('/api/companies/lookup?code=' . strtoupper($company->id));

        $response->assertOk();
        $response->assertJsonPath('company.id', $company->id);
    }

    public function test_lookup_still_matches_company_code_case_insensitively(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN0KUS',
        ]);

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->getJson('/api/companies/lookup?code=gen0kus');

        $response->assertOk();
        $response->assertJsonPath('company.id', $company->id);
    }
}
