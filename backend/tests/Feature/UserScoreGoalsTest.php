<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\Goal;
use App\Models\GoalTask;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class UserScoreGoalsTest extends TestCase
{
    use RefreshDatabase;

    private function makeCompany(string $name, string $code): Company
    {
        return Company::create([
            'id' => (string) Str::uuid(),
            'name' => $name,
            'code' => $code,
        ]);
    }

    private function makeUserInCompany(Company $company): User
    {
        return User::factory()->create([
            'company_code' => $company->code,
        ]);
    }

    public function test_goal_score_comes_from_goals_and_daily_tracker_stays_an_average(): void
    {
        $company = $this->makeCompany('GoalCo', 'GOAL001');
        $user = $this->makeUserInCompany($company);

        Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $user->id,
            'company_id' => (string) $company->id,
            'category' => 'PERSONAL',
            'title' => 'Completed goal',
            'status' => 'COMPLETED',
            'goal_type' => 'MERIT',
            'direction' => 'GAIN',
            'target_value' => 10,
            'current_value' => 10,
            'unit' => 'pts',
            'target_period' => 'NONE',
            'start_date' => '2026-07-01',
            'target_date' => '2026-07-31',
            'progress' => 100,
        ]);

        $milestone = Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $user->id,
            'company_id' => (string) $company->id,
            'category' => 'PROFESSIONAL',
            'title' => 'Milestone goal',
            'status' => 'IN_PROGRESS',
            'goal_type' => 'MILESTONE',
            'direction' => 'GAIN',
            'target_value' => 0,
            'current_value' => 0,
            'unit' => '',
            'target_period' => 'NONE',
            'start_date' => '2026-07-01',
            'target_date' => '2026-07-31',
            'progress' => 0,
        ]);

        GoalTask::create([
            'id' => (string) Str::uuid(),
            'goal_id' => (string) $milestone->id,
            'title' => 'Task one',
            'status' => 'DONE',
            'is_complete' => true,
            'sort_order' => 0,
            'weight' => 1,
        ]);
        GoalTask::create([
            'id' => (string) Str::uuid(),
            'goal_id' => (string) $milestone->id,
            'title' => 'Task two',
            'status' => 'IN_PROGRESS',
            'is_complete' => false,
            'sort_order' => 1,
            'weight' => 1,
        ]);

        Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $user->id,
            'company_id' => (string) $company->id,
            'category' => 'CONTRIBUTION',
            'title' => 'Merit goal',
            'status' => 'IN_PROGRESS',
            'goal_type' => 'MERIT',
            'direction' => 'GAIN',
            'target_value' => 100,
            'current_value' => 20,
            'unit' => 'pts',
            'target_period' => 'NONE',
            'start_date' => '2026-07-01',
            'target_date' => '2026-07-31',
            'progress' => 20,
        ]);

        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-07-27',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 3,
            'todo_list_score_daily_contribution' => 1,
            'todo_list_included_in_total' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-07-28',
            'call' => true,
            'steps' => true,
            'exercise' => false,
            'meditation' => false,
            'learning' => true,
            'add_value' => false,
            'todo_list_score' => 99,
            'todo_list_score_daily_contribution' => 99,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        $this->assertEquals(65.0, $breakdown['goalScore']);
        $this->assertEquals(75.0, $breakdown['coreTaskScore']);
        // The leaderboard ranking score comes only from daily tracker
        // activity now, so overallScore equals coreTaskScore -- goalScore
        // is still computed and returned above for informational display.
        $this->assertEquals(75.0, $breakdown['overallScore']);
    }
}
