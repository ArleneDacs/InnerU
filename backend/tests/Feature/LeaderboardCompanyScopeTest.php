<?php

namespace Tests\Feature;

use App\Models\CoachGroup;
use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class LeaderboardCompanyScopeTest extends TestCase
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

    private function makeGroup(
        User $coach,
        string $name,
        array $memberIds,
    ): CoachGroup {
        return CoachGroup::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => $name,
            'member_ids' => array_values($memberIds),
            'member_count' => count($memberIds),
            'company_code' => $coach->company_code,
            'company_name' => $coach->company_name,
        ]);
    }

    public function test_a_user_with_no_resolvable_company_sees_all_users_and_groups(): void
    {
        $companyA = $this->makeCompany('CompanyA', 'COMPA');
        $companyB = $this->makeCompany('CompanyB', 'COMPB');

        $blankCoach = User::factory()->create([
            'company_id' => null,
            'company_code' => null,
            'company_name' => null,
            'active_company_id' => null,
            'active_company_code' => null,
            'active_company_name' => null,
            'is_coach' => true,
        ]);
        $companyAUser = User::factory()->create([
            'company_id' => $companyA->id,
            'company_code' => $companyA->code,
            'company_name' => $companyA->name,
        ]);
        $companyBUser = User::factory()->create([
            'company_id' => $companyB->id,
            'company_code' => $companyB->code,
            'company_name' => $companyB->name,
        ]);

        $this->makeGroup($companyAUser, 'Alpha Group', [(string) $companyAUser->id]);
        $this->makeGroup($companyBUser, 'Beta Group', [(string) $companyBUser->id]);

        Sanctum::actingAs($blankCoach);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $this->assertEqualsCanonicalizing(
            [
                (string) $blankCoach->id,
                (string) $companyAUser->id,
                (string) $companyBUser->id,
            ],
            collect($response->json('companyLeaderboard'))->pluck('userId')->all(),
        );
        $this->assertEqualsCanonicalizing(
            ['Alpha Group', 'Beta Group'],
            collect($response->json('groupLeaderboards'))->pluck('groupName')->all(),
        );
    }

    public function test_a_user_with_a_company_sees_only_their_companys_users_and_groups(): void
    {
        $companyA = $this->makeCompany('CompanyA', 'COMPA');
        $companyB = $this->makeCompany('CompanyB', 'COMPB');

        $userA = User::factory()->create([
            'company_id' => $companyA->id,
            'company_code' => $companyA->code,
            'company_name' => $companyA->name,
        ]);
        $userB = User::factory()->create([
            'company_id' => $companyB->id,
            'company_code' => $companyB->code,
            'company_name' => $companyB->name,
        ]);
        $this->makeGroup($userA, 'Alpha Group', [(string) $userA->id]);
        $this->makeGroup($userB, 'Beta Group', [(string) $userB->id]);

        Sanctum::actingAs($userA);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $ids = collect($response->json('companyLeaderboard'))->pluck('userId');

        $this->assertTrue($ids->contains((string) $userA->id));
        $this->assertFalse($ids->contains((string) $userB->id));
        $this->assertEqualsCanonicalizing(
            ['Alpha Group'],
            collect($response->json('groupLeaderboards'))->pluck('groupName')->all(),
        );
    }

    public function test_a_company_with_a_future_period_keeps_everyones_scores_at_zero_until_the_start_date(): void
    {
        $company = $this->makeCompany('Future Company', 'FUT001');
        $company->update([
            'leaderboard_period_start' => '2026-08-01',
            'leaderboard_period_end' => '2026-12-31',
        ]);

        $userOne = User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);
        $userTwo = User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

        DailyTracker::create([
            'user_id' => (string) $userOne->id,
            'username' => $userOne->name,
            'date' => '2026-07-27',
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
            'todo_list_score' => 100,
            'todo_list_included_in_total' => true,
        ]);
        DailyTracker::create([
            'user_id' => (string) $userTwo->id,
            'username' => $userTwo->name,
            'date' => '2026-07-27',
            'call' => false,
            'steps' => false,
            'exercise' => false,
            'meditation' => false,
            'learning' => false,
            'add_value' => false,
            'todo_list_score' => 0,
            'todo_list_included_in_total' => false,
        ]);

        Sanctum::actingAs($userOne);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $response->assertJsonPath('company.leaderboardPeriodStart', '2026-08-01');
        $response->assertJsonPath('company.leaderboardPeriodEnd', '2026-12-31');

        foreach ($response->json('companyLeaderboard') as $entry) {
            $this->assertSame(0.0, (float) $entry['overallScore']);
        }
    }
}
