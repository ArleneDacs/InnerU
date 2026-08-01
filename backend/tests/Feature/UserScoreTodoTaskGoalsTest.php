<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\TodoTask;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Tests\TestCase;

class UserScoreTodoTaskGoalsTest extends TestCase
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

    public function test_goal_score_falls_back_to_todo_tasks_when_the_user_has_no_goal_records(): void
    {
        // Reproduces the real production scenario: the new Goal/GoalTask
        // tables are empty (nobody has adopted that feature yet), but the
        // actual "Goals" screen everyone uses (todo_list.dart) is backed by
        // TodoTask. The leaderboard's goalScore must match what that
        // screen's own "_todoScore" shows: a flat average of each task's
        // progress (subtask completion ratio, or 100/0 if no subtasks)
        // across ALL of the user's tasks -- not the per-category Goal
        // formula, which has no data to work with here at all.
        $company = $this->makeCompany('Gencys', 'GEN0KUS');
        $user = User::factory()->create(['company_code' => $company->code]);

        // Personal: 1 of 4 subtasks complete -> 25%.
        TodoTask::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'title' => 'Get that healthy and sexy body',
            'due_date' => '2026-12-31',
            'tag' => 'personal',
            'is_completed' => false,
            'sub_tasks' => [
                ['id' => 'a', 'title' => 'Do walking everyday', 'isCompleted' => true],
                ['id' => 'b', 'title' => 'apply to gym', 'isCompleted' => false],
                ['id' => 'c', 'title' => 'cut out carbs', 'isCompleted' => false],
                ['id' => 'd', 'title' => 'sleep 8 hours', 'isCompleted' => false],
            ],
        ]);

        // Professional: 1 of 3 subtasks complete -> 33.33%.
        TodoTask::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'title' => 'Get promoted',
            'due_date' => '2026-12-31',
            'tag' => 'professional',
            'is_completed' => false,
            'sub_tasks' => [
                ['id' => 'a', 'title' => 'Finish course', 'isCompleted' => true],
                ['id' => 'b', 'title' => 'Ask for feedback', 'isCompleted' => false],
                ['id' => 'c', 'title' => 'Update resume', 'isCompleted' => false],
            ],
        ]);

        // Contribution: no subtasks, not completed -> 0%.
        TodoTask::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'title' => 'Volunteer more',
            'due_date' => '2026-12-31',
            'tag' => 'contribution',
            'is_completed' => false,
            'sub_tasks' => [],
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // (25 + 33.33... + 0) / 3 = 19.44... -> rounds to 19, matching the
        // Goals page's own _todoScore.round() display of "19%".
        $this->assertEquals(19.0, $breakdown['goalScore']);
    }

    public function test_everyday_goal_score_uses_calendar_completion_dates(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-07-29 12:00:00'));

        try {
            $user = User::factory()->create();

            TodoTask::create([
                'id' => (string) Str::uuid(),
                'user_id' => $user->id,
                'title' => 'Check in daily',
                'goal_type' => 'EVERYDAY',
                'start_date' => '2026-07-27',
                'due_date' => '2026-07-29',
                'tag' => 'personal',
                'is_completed' => false,
                'completion_dates' => [
                    '2026-07-27',
                    '2026-07-29T08:00:00+08:00',
                    '2026-07-29',
                ],
                'sub_tasks' => [],
            ]);

            $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

            $this->assertEquals(67.0, $breakdown['goalScore']);
        } finally {
            Carbon::setTestNow();
        }
    }

    public function test_period_goal_score_divides_one_time_completion_by_the_full_program_length(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-08-01 12:00:00'));

        try {
            $company = Company::create([
                'id' => (string) Str::uuid(),
                'name' => 'Gencys',
                'code' => 'GEN0KUS',
                'leaderboard_period_start' => '2026-08-01',
                'leaderboard_period_end' => '2026-12-31',
            ]);
            $user = User::factory()->create(['company_code' => $company->code]);

            TodoTask::create([
                'id' => (string) Str::uuid(),
                'user_id' => $user->id,
                'title' => 'Finish one easy goal',
                'goal_type' => 'LONG_TERM',
                'start_date' => '2026-08-01',
                'due_date' => '2026-08-01',
                'tag' => 'personal',
                'is_completed' => true,
                'completed_at' => '2026-08-01 08:00:00',
                'completion_dates' => [],
                'sub_tasks' => [],
            ]);

            $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

            // Aug 1-Dec 31 inclusive is 153 days. A one-time goal earns
            // one day-credit, so it must not become 100% on day one.
            $this->assertEqualsWithDelta(0.65, $breakdown['goalScore'], 0.01);
            $this->assertEqualsWithDelta(0.65, $breakdown['overallScore'], 0.01);
        } finally {
            Carbon::setTestNow();
        }
    }

    public function test_period_everyday_goal_score_uses_completed_days_over_the_full_program_length(): void
    {
        Carbon::setTestNow(Carbon::parse('2026-08-03 12:00:00'));

        try {
            $company = Company::create([
                'id' => (string) Str::uuid(),
                'name' => 'Gencys',
                'code' => 'GEN0KUS',
                'leaderboard_period_start' => '2026-08-01',
                'leaderboard_period_end' => '2026-12-31',
            ]);
            $user = User::factory()->create(['company_code' => $company->code]);

            TodoTask::create([
                'id' => (string) Str::uuid(),
                'user_id' => $user->id,
                'title' => 'Walk every day',
                'goal_type' => 'EVERYDAY',
                'start_date' => '2026-08-01',
                'due_date' => '2026-12-31',
                'tag' => 'personal',
                'is_completed' => false,
                'completion_dates' => [
                    '2026-08-01',
                    '2026-08-03',
                ],
                'sub_tasks' => [],
            ]);

            $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

            // 2 completed days / 153 program days = 1.31%.
            $this->assertEqualsWithDelta(1.31, $breakdown['goalScore'], 0.01);
        } finally {
            Carbon::setTestNow();
        }
    }
}
