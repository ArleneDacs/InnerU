<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommunityMentionTest extends TestCase
{
    use RefreshDatabase;

    public function test_search_returns_matching_users_in_the_same_company_only(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        $sameCompany = User::factory()->create(['company_code' => 'ACME', 'name' => 'Jordan Rivera']);
        $otherCompany = User::factory()->create(['company_code' => 'OTHER', 'name' => 'Jordan Smith']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=Jordan');

        $response->assertOk();
        $names = collect($response->json())->pluck('name')->all();
        $this->assertContains('Jordan Rivera', $names);
        $this->assertNotContains('Jordan Smith', $names);
    }

    public function test_search_is_capped_at_10_results(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        User::factory()->count(15)->create(['company_code' => 'ACME', 'name' => 'Test Match User']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=Test');

        $response->assertOk();
        $this->assertLessThanOrEqual(10, count($response->json()));
    }

    public function test_a_blank_query_returns_an_empty_list_not_the_whole_company(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        User::factory()->count(3)->create(['company_code' => 'ACME']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=');

        $response->assertOk();
        $this->assertCount(0, $response->json());
    }
}
