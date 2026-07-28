<?php

namespace Tests\Feature;

use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\Goal;
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
        // goalScore = the one in-period record's todo_list_score (50), not 90 or 99.
        $this->assertEquals(50.0, $breakdown['goalScore']);
        $this->assertEquals(35.0, $breakdown['overallScore']);
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
        // averaged with Aug 5's 80.
        $this->assertEquals(30.0, $breakdown['goalScore']);
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

    public function test_the_goals_based_score_still_applies_even_when_a_leaderboard_period_is_configured(): void
    {
        Carbon::setTestNow('2030-01-01');

        $company = $this->makeCompanyWithPeriod('2026-08-01', '2026-08-05');
        $user = $this->makeUserInCompany($company);

        // Goals are a date-independent "current status" snapshot -- the
        // Goals page shows the exact same percentage no matter what
        // leaderboard period is configured, so goalScore must match it
        // exactly rather than falling back to a DailyTracker's legacy
        // todo-list score. One PERSONAL goal at 100%, PROFESSIONAL and
        // CONTRIBUTION empty at 0% each -> (100+0+0)/3 = 33.3, the same
        // math the Goals page itself uses.
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

        $this->assertEquals(33.3, $breakdown['goalScore']);
    }
}
