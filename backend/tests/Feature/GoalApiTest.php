<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class GoalApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_goal_creation_persists_the_provided_start_date(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'GoalCo',
            'code' => 'GOAL01',
        ]);

        $user = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/goals', [
            'category' => 'PERSONAL',
            'title' => 'Plan the launch',
            'start_date' => '2026-07-01',
            'target_date' => '2026-09-01',
            'target_value' => 100,
            'current_value' => 25,
            'unit' => 'pts',
        ]);

        $response->assertCreated()
            ->assertJsonPath('goal.title', 'Plan the launch');

        $this->assertDatabaseHas('goals', [
            'user_id' => $user->id,
            'company_id' => $company->id,
            'start_date' => '2026-07-01',
            'target_date' => '2026-09-01',
        ]);
    }
}
