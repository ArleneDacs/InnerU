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

    public function test_a_user_with_no_resolvable_company_only_sees_themselves_but_falls_back_to_all_groups(): void
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
            [(string) $blankCoach->id],
            collect($response->json('companyLeaderboard'))->pluck('userId')->all(),
        );
        // No company to scope by -- per spec, fall back to showing every
        // group rather than an empty tab. Users/scores stay strictly
        // scoped (asserted above); only groups get this fallback.
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

    public function test_shared_company_codes_or_names_do_not_leak_other_company_members(): void
    {
        $companyA = $this->makeCompany('Shared Company', 'SHARED-A');
        $companyB = $this->makeCompany('Shared Company', 'SHARED-B');

        $userA = User::factory()->create([
            'company_id' => $companyA->id,
            'active_company_id' => $companyA->id,
            'company_code' => $companyA->code,
            'active_company_code' => $companyA->code,
            'company_name' => $companyA->name,
            'active_company_name' => $companyA->name,
        ]);
        $userB = User::factory()->create([
            'company_id' => $companyB->id,
            'active_company_id' => $companyB->id,
            'company_code' => $companyB->code,
            'active_company_code' => $companyB->code,
            'company_name' => $companyB->name,
            'active_company_name' => $companyB->name,
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

    public function test_a_coachs_group_still_shows_even_when_it_has_no_members_yet(): void
    {
        $company = $this->makeCompany('CompanyA', 'COMPA');

        $coach = User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
            'is_coach' => true,
        ]);

        $this->makeGroup($coach, 'Coach Only Group', []);

        Sanctum::actingAs($coach);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $this->assertEqualsCanonicalizing(
            ['Coach Only Group'],
            collect($response->json('groupLeaderboards'))->pluck('groupName')->all(),
        );
    }

    public function test_the_viewer_always_appears_in_their_own_company_leaderboard_even_with_messy_company_id(): void
    {
        // A same-company user with a clean company_id, so the "exact id
        // match" branch finds something and would otherwise short-circuit
        // before ever falling back to the code/name-based query.
        $company = $this->makeCompany('MessyCo', 'MESSY01');
        User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

        // The viewer: only resolvable via company_code/company_name,
        // company_id itself is blank -- a realistic data-quality gap.
        $viewer = User::factory()->create([
            'company_id' => null,
            'active_company_id' => null,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

        Sanctum::actingAs($viewer);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $ids = collect($response->json('companyLeaderboard'))->pluck('userId');

        $this->assertTrue(
            $ids->contains((string) $viewer->id),
            'The viewer must always see their own entry in their own company leaderboard.',
        );
    }

    public function test_groups_fall_back_to_showing_everyone_when_none_match_the_viewers_company(): void
    {
        $viewerCompany = $this->makeCompany('ViewerCo', 'VIEWCO');
        $otherCompany = $this->makeCompany('OtherCo', 'OTHERCO');

        $viewer = User::factory()->create([
            'company_id' => $viewerCompany->id,
            'company_code' => $viewerCompany->code,
            'company_name' => $viewerCompany->name,
        ]);

        // Every existing group belongs to a DIFFERENT company than the
        // viewer -- none should match, so the fallback should kick in.
        $otherCoach = User::factory()->create([
            'company_id' => $otherCompany->id,
            'company_code' => $otherCompany->code,
            'company_name' => $otherCompany->name,
            'is_coach' => true,
        ]);
        $this->makeGroup($otherCoach, 'Other Group', [(string) $otherCoach->id]);

        Sanctum::actingAs($viewer);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $this->assertEqualsCanonicalizing(
            ['Other Group'],
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
