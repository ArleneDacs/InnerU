<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\CoachMentee;
use App\Models\Goal;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CoachGoalsRosterTest extends TestCase
{
    use RefreshDatabase;

    public function test_roster_groups_goals_by_mentee_for_the_requesting_coach(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Abundance',
            'code' => 'ABU15DN',
        ]);

        $coach = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);
        $mentee = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);
        $otherMentee = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);

        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'mentee_name' => 'Maychell Alcorin',
        ]);

        Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $mentee->id,
            'company_id' => $company->id,
            'category' => 'PERSONAL',
            'title' => 'Run 100 km',
            'status' => 'IN_PROGRESS',
            'progress' => 40,
            'goal_type' => 'MERIT',
            'target_period' => 'NONE',
            'direction' => 'GAIN',
            'target_value' => 100,
            'current_value' => 40,
            'unit' => 'km',
            'start_date' => '2026-07-01',
            'target_date' => '2026-09-01',
        ]);

        // A goal belonging to a mentee this coach does NOT have an active
        // assignment for must never appear in the roster.
        Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $otherMentee->id,
            'company_id' => $company->id,
            'category' => 'PROFESSIONAL',
            'title' => 'Should not appear',
            'status' => 'NOT_STARTED',
            'progress' => 0,
            'goal_type' => 'MERIT',
            'target_period' => 'NONE',
            'direction' => 'GAIN',
            'target_value' => 10,
            'current_value' => 0,
            'unit' => 'pts',
            'start_date' => '2026-07-01',
            'target_date' => '2026-09-01',
        ]);

        Sanctum::actingAs($coach);

        $response = $this->getJson('/api/coach/goals');

        $response->assertOk();
        $roster = $response->json('roster');
        $this->assertCount(1, $roster);
        $this->assertSame('Maychell Alcorin', $roster[0]['menteeName']);
        $this->assertCount(1, $roster[0]['goals']);
        $this->assertSame('Run 100 km', $roster[0]['goals'][0]['title']);
    }

    public function test_roster_is_empty_for_a_coach_with_no_mentees(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Abundance',
            'code' => 'ABU15DN',
        ]);
        $coach = User::factory()->create([
            'company_id' => $company->id,
            'active_company_id' => $company->id,
        ]);
        Sanctum::actingAs($coach);

        $response = $this->getJson('/api/coach/goals');

        $response->assertOk();
        $this->assertSame([], $response->json('roster'));
    }
}
