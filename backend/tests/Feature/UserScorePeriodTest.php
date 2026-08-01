<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\Goal;
use App\Models\GoalTask;
use App\Models\TodoTask;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Tests\TestCase;

class UserScorePeriodTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        Carbon::setTestNow(null);
        parent::tearDown();
    }

    private function makeCompanyWithPeriod(string $start, string $end): Company
    {
        return Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Gencys',
            'code' => 'GEN001',
            'leaderboard_period_start' => $start,
            'leaderboard_period_end' => $end,
        ]);
    }

    private function makeUserInCompany(Company $company): User
    {
        return User::factory()->create([
            'company_code' => $company->code,
        ]);
    }

    public function test_a_company_with_no_period_behaves_exactly_as_before(): void
    {
        $company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'NoPeriodCo',
            'code' => 'NPC001',
        ]);
        $user = $this->makeUserInCompany($company);

        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-01-01',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-01-02',
            'call' => false,
            'steps' => false,
            'exercise' => false,
            'meditation' => false,
            'learning' => false,
            'add_value' => false,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Existing behavior: sum of recorded days' scores / number of recorded days.
        // Day 1 = 100, day 2 = 0 -> average 50.
        $this->assertEquals(50.0, $breakdown['coreTaskScore']);
    }

    public function test_only_activity_within_the_period_counts(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-05');
        $user = $this->makeUserInCompany($company);

        // Before the period: fully completed, high todo-list score. Must be ignored entirely.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-07-15',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 90,
            'todo_list_included_in_total' => true,
        ]);

        // Within the period: fully completed, todo-list score 50.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-03',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 50,
            'todo_list_included_in_total' => true,
        ]);

        // After the period: must also be ignored.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-10',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 99,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Period is Aug 1-5 inclusive = 5 days. Only Aug 3 counts, at 100% completion.
        // coreTaskScore = 100 / 5 = 20.
        $this->assertEquals(20.0, $breakdown['coreTaskScore']);
        // Legacy tracker goal score is spread across the full 5-day period:
        // 50 / 5 = 10.
        $this->assertEquals(10.0, $breakdown['goalScore']);
        $this->assertEquals(15.0, $breakdown['overallScore']);
    }

    public function test_the_divisor_is_the_full_period_length_not_the_recorded_day_count(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-10');
        $user = $this->makeUserInCompany($company);

        // Only 2 of the 10 period days have any record, both 100% complete.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-02',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-04',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Period Aug 1-10 inclusive = 10 days. Two 100% days sum to 200.
        // 200 / 10 = 20 -- NOT 200 / 2 = 100 (which is what today's
        // all-time-average logic would produce for the same 2 records).
        $this->assertEquals(20.0, $breakdown['coreTaskScore']);
    }

    public function test_period_core_task_score_uses_the_saved_daily_tracker_task_snapshot_when_present(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-10');
        $user = $this->makeUserInCompany($company);

        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-02',
            'call' => true,
            'steps' => false,
            'exercise' => false,
            'meditation' => false,
            'learning' => false,
            'add_value' => false,
            'custom_daily_tasks' => [
                '__snapshotTaskIds' => ['steps', 'meditation'],
                'steps' => [
                    'title' => 'Steps',
                    'completed' => true,
                    'isDefault' => true,
                ],
                'meditation' => [
                    'title' => 'Meditation',
                    'completed' => false,
                    'isDefault' => true,
                ],
            ],
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Custom daily tracker lists can vary per user/day. The saved
        // snapshot says this day had 2 tasks with 1 complete, so the period
        // contribution is 50 / 10 days = 5, not the fallback 1-of-6 default
        // task score.
        $this->assertEquals(5.0, $breakdown['coreTaskScore']);
    }

    public function test_goal_score_is_the_latest_within_period_record_not_averaged(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-31');
        $user = $this->makeUserInCompany($company);

        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-05',
            'todo_list_score' => 80,
            'todo_list_included_in_total' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-20',
            'todo_list_score' => 30,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // Latest record by date is Aug 20 (score 30) -- must not be
        // averaged with Aug 5's 80. It is still spread across the full
        // 31-day period, so 30 / 31 rounds to 1.0.
        $this->assertEquals(1.0, $breakdown['goalScore']);
    }

    public function test_a_company_with_a_period_and_zero_records_in_it_scores_zero(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-31');
        $user = $this->makeUserInCompany($company);

        // Old data exists, but entirely before the period.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-01-01',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 90,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        $this->assertEquals(0.0, $breakdown['coreTaskScore']);
        $this->assertEquals(0.0, $breakdown['goalScore']);
        $this->assertEquals(0.0, $breakdown['overallScore']);
    }

    public function test_todo_tasks_starting_in_the_period_are_divided_by_the_full_period_length(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-12-31');
        $user = $this->makeUserInCompany($company);

        // This task started before the period and must be ignored.
        TodoTask::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'title' => 'Pre-period task',
            'goal_type' => 'LONG_TERM',
            'start_date' => '2026-07-15',
            'due_date' => '2026-12-31',
            'is_completed' => true,
            'sub_tasks' => [],
        ]);

        // These tasks start inside the configured period and should count.
        TodoTask::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'title' => 'In-period task one',
            'goal_type' => 'LONG_TERM',
            'start_date' => '2026-08-01',
            'due_date' => '2026-12-31',
            'is_completed' => true,
            'sub_tasks' => [],
        ]);
        TodoTask::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'title' => 'In-period task two',
            'goal_type' => 'LONG_TERM',
            'start_date' => '2026-08-15',
            'due_date' => '2026-12-31',
            'is_completed' => false,
            'sub_tasks' => [],
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        // The pre-period task is ignored. One completed in-period task
        // earns one day-credit across the 153-day period, averaged with
        // the incomplete in-period task: (0.65 + 0) / 2 = 0.33.
        $this->assertEqualsWithDelta(0.33, $breakdown['goalScore'], 0.01);
        $this->assertEqualsWithDelta(0.33, $breakdown['overallScore'], 0.01);
    }

    public function test_a_period_starts_at_the_companys_local_midnight_even_when_utc_is_still_the_previous_day(): void
    {
        Carbon::setTestNow(Carbon::create(2026, 7, 31, 16, 0, 0, 'UTC'));

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-12-31');
        $user = $this->makeUserInCompany($company);

        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-01',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 100,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        $this->assertGreaterThan(0.0, $breakdown['coreTaskScore']);
        $this->assertGreaterThan(0.0, $breakdown['overallScore']);
    }

    public function test_batch_resolution_applies_period_scoring_too(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-10');
        $userInPeriod = $this->makeUserInCompany($company);
        $otherCompany = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'NoPeriodCo2',
            'code' => 'NPC002',
        ]);
        $userWithoutPeriod = $this->makeUserInCompany($otherCompany);

        DailyTracker::create([
            'user_id' => (string) $userInPeriod->id,
            'username' => $userInPeriod->name,
            'date' => '2026-08-02',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $userWithoutPeriod->id,
            'username' => $userWithoutPeriod->name,
            'date' => '2026-08-02',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);

        $breakdowns = app(UserScoreService::class)->resolveBreakdownForUsers(
            collect([$userInPeriod->fresh(), $userWithoutPeriod->fresh()])
        );

        // In-period user: 100 / 10-day period = 10.
        $this->assertEquals(10.0, $breakdowns[(string) $userInPeriod->id]['coreTaskScore']);
        // No-period user: unchanged all-time-average behavior, 1 recorded
        // day at 100% -> 100.
        $this->assertEquals(100.0, $breakdowns[(string) $userWithoutPeriod->id]['coreTaskScore']);
    }

    public function test_the_goals_based_score_is_spread_across_the_configured_period(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-05');
        $user = $this->makeUserInCompany($company);

        // The raw Goals page score is still 33.3, but leaderboard scoring
        // now spreads that across the full configured period. For an
        // 5-day window, 33.3 / 5 = 6.7.
        Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $user->id,
            'company_id' => (string) $company->id,
            'category' => 'PERSONAL',
            'title' => 'Old completed goal',
            'status' => 'COMPLETED',
            'goal_type' => 'MERIT',
            'direction' => 'GAIN',
            'target_value' => 10,
            'current_value' => 10,
            'unit' => 'pts',
            'target_period' => 'NONE',
            'start_date' => '2026-01-01',
            'target_date' => '2026-01-31',
            'progress' => 100,
        ]);

        // A DailyTracker todo-list score must NOT override the real
        // Goals-based score.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-08-03',
            'todo_list_score' => 40,
            'todo_list_included_in_total' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        $this->assertEquals(6.7, $breakdown['goalScore']);
    }

    public function test_the_full_leaderboard_formula_matches_spec_for_a_configured_period(): void
    {
        // Locks in the exact formula for a period-configured company:
        //   Period Days        = End - Start + 1
        //   Daily Tracker Avg   = Total Daily Tracker Score / Period Days
        //   Goals Avg           = (Personal + Professional + Contribution) / 3
        //   Final Score         = (Daily Tracker Avg + Goals Avg) / 2
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-01-01', '2026-01-10');
        $user = $this->makeUserInCompany($company);

        // Goals: Personal 100, Professional 75 (1 DONE + 1 IN_PROGRESS
        // milestone task), Contribution 20 -> raw avg = (100+75+20)/3 = 65.
        // With a 10-day period, that becomes 6.5 on the leaderboard.
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
            'start_date' => '2026-01-01',
            'target_date' => '2026-01-10',
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
            'start_date' => '2026-01-01',
            'target_date' => '2026-01-10',
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
            'start_date' => '2026-01-01',
            'target_date' => '2026-01-10',
            'progress' => 20,
        ]);

        // Daily tracker: day 1 fully complete (100), day 2 half complete
        // (50) -> sum 150, divided by the FULL 10-day period (not just the
        // 2 days with logs) = 15.
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-01-01',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => '2026-01-02',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => false,
            'learning' => false,
            'add_value' => false,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        $this->assertEquals(6.5, $breakdown['goalScore']);
        $this->assertEquals(15.0, $breakdown['coreTaskScore']);
        $this->assertEqualsWithDelta(10.75, $breakdown['overallScore'], 0.01);
    }
}
