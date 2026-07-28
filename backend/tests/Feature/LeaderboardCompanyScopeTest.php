<?php

namespace Tests\Feature;

use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class LeaderboardCompanyScopeTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        Carbon::setTestNow(null);
        parent::tearDown();
    }

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
        ?string $companyId = null,
    ): CoachGroup {
        return CoachGroup::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'company_id' => $companyId ?? $coach->company_id,
            'coach_ids' => [(string) $coach->id],
            'name' => $name,
            'member_ids' => array_values($memberIds),
            'member_count' => count($memberIds),
            'company_code' => $coach->company_code,
            'company_name' => $coach->company_name,
        ]);
    }

    public function test_a_user_with_no_resolvable_company_only_sees_themselves_and_no_groups(): void
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
        $this->assertSame([], $response->json('groupLeaderboards'));
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

    public function test_each_group_reports_the_viewers_own_company_id_and_name(): void
    {
        $company = $this->makeCompany('CompanyA', 'COMPA');
        $viewer = User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);
        $this->makeGroup($viewer, 'Alpha Group', [(string) $viewer->id]);

        Sanctum::actingAs($viewer);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $group = collect($response->json('groupLeaderboards'))->firstWhere('groupName', 'Alpha Group');

        $this->assertSame($company->id, $group['companyId']);
        $this->assertSame('CompanyA', $group['companyName']);
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

    public function test_a_group_matches_by_its_stored_company_code_when_company_id_was_never_backfilled(): void
    {
        // This is the real-world case: a group created long ago already
        // has company_code/company_name stamped (that's been happening
        // since the group-creation feature was built), but its NEW
        // company_id column is null because the coach's own company_id
        // field is blank -- the backfill migration has nothing to copy
        // from. The coach's other company fields are blank too, so the
        // dynamic "is this coach currently in my company" check also
        // can't resolve them. company_code is the one signal that's
        // reliably been there since the group was first created.
        $company = $this->makeCompany('Gencys', 'GENTIKG');
        $viewer = User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

        $coach = User::factory()->create([
            'company_id' => null,
            'active_company_id' => null,
            'company_code' => null,
            'active_company_code' => null,
            'company_name' => null,
            'active_company_name' => null,
            'is_coach' => true,
        ]);

        $group = CoachGroup::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'company_id' => null,
            'coach_ids' => [(string) $coach->id],
            'name' => "Maychell's Circle",
            'member_ids' => [],
            'member_count' => 0,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

        Sanctum::actingAs($viewer);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $this->assertEqualsCanonicalizing(
            ["Maychell's Circle"],
            collect($response->json('groupLeaderboards'))->pluck('groupName')->all(),
        );
    }

    public function test_a_matched_groups_members_still_show_even_when_their_own_company_fields_are_messy(): void
    {
        // Same real-world setup as the company_code test above, but now
        // with an actual mentee assigned to the coach's group. The
        // member's own company fields are just as blank as the coach's --
        // once the group itself is confirmed to be in the viewer's
        // company (via company_code), its listed members should be
        // trusted by that association, not independently re-checked
        // against their own possibly-messy company data.
        $company = $this->makeCompany('Gencys', 'GENTIKG');
        $viewer = User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

        $coach = User::factory()->create([
            'company_id' => null,
            'active_company_id' => null,
            'company_code' => null,
            'active_company_code' => null,
            'company_name' => null,
            'active_company_name' => null,
            'is_coach' => true,
        ]);

        $member = User::factory()->create([
            'name' => 'Messy Member',
            'company_id' => null,
            'active_company_id' => null,
            'company_code' => null,
            'active_company_code' => null,
            'company_name' => null,
            'active_company_name' => null,
        ]);

        $group = CoachGroup::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'company_id' => null,
            'coach_ids' => [(string) $coach->id],
            'name' => "Maychell's Circle",
            'member_ids' => [],
            'member_count' => 1,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $member->id,
            'group_id' => $group->id,
            'group_name' => $group->name,
        ]);

        Sanctum::actingAs($viewer);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $groupPayload = collect($response->json('groupLeaderboards'))
            ->firstWhere('groupName', "Maychell's Circle");

        $this->assertNotNull($groupPayload);
        $this->assertEqualsCanonicalizing(
            ['Messy Member'],
            collect($groupPayload['entries'])->pluck('name')->all(),
        );
    }

    public function test_a_group_matches_by_its_stored_company_id_even_if_the_coachs_own_data_has_since_drifted(): void
    {
        $company = $this->makeCompany('CompanyA', 'COMPA');
        $viewer = User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

        // The coach's OWN current company fields point somewhere else
        // entirely now (simulating a coach who has since moved
        // companies, or whose record has drifted) -- the dynamic
        // "is this coach currently in my company" check would fail for
        // them. The group itself still remembers what company it was
        // created under via its own stored company_id, which is what
        // should govern visibility, not the coach's present-day data.
        $driftedCoach = User::factory()->create([
            'company_id' => 'some-other-company-id',
            'company_code' => 'OTHER',
            'company_name' => 'Other Co',
            'is_coach' => true,
        ]);

        $this->makeGroup($driftedCoach, 'Stamped Group', [], companyId: $company->id);

        Sanctum::actingAs($viewer);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();
        $this->assertEqualsCanonicalizing(
            ['Stamped Group'],
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

    public function test_groups_stay_empty_when_none_match_the_viewers_company_no_fallback(): void
    {
        $viewerCompany = $this->makeCompany('ViewerCo', 'VIEWCO');
        $otherCompany = $this->makeCompany('OtherCo', 'OTHERCO');

        $viewer = User::factory()->create([
            'company_id' => $viewerCompany->id,
            'company_code' => $viewerCompany->code,
            'company_name' => $viewerCompany->name,
        ]);

        // Every existing group belongs to a DIFFERENT company than the
        // viewer -- none should match, and none should leak in as a
        // fallback either. Groups are scoped exactly like users: strict,
        // no "show everything" exception.
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
        $this->assertSame([], $response->json('groupLeaderboards'));
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

    public function test_a_tracker_row_dated_on_or_after_a_future_period_start_is_still_ignored_until_that_date_actually_arrives(): void
    {
        // Regression test: a device with a clock/timezone ahead of the
        // server (or a manually-entered date) can create a DailyTracker
        // row dated on/after the period's start date even though "today"
        // hasn't reached it yet. The whereBetween query in
        // scoreBreakdownForPeriod would happily match that row -- the
        // score must stay at 0 until the period has actually started,
        // regardless of what dates happen to exist in daily_trackers.
        Carbon::setTestNow('2026-07-29');

        $company = $this->makeCompany('Future Company Two', 'FUT002');
        $company->update([
            'leaderboard_period_start' => '2026-08-01',
            'leaderboard_period_end' => '2026-12-31',
        ]);

        $user = User::factory()->create([
            'company_id' => $company->id,
            'company_code' => $company->code,
            'company_name' => $company->name,
        ]);

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

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/leaderboard');

        $response->assertOk();

        foreach ($response->json('companyLeaderboard') as $entry) {
            $this->assertSame(0.0, (float) $entry['overallScore']);
        }
    }
}
