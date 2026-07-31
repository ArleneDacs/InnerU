<?php

namespace Tests\Feature;

use App\Models\CoachMentee;
use App\Models\Company;
use App\Models\Goal;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

/**
 * The coach Quests roster links each row to the mentee's quest detail screen.
 * Before this, every read endpoint on a goal was strictly owner-only, so a
 * coach opening a mentee's quest got a 401 on every request — and the Flutter
 * polling stream swallows that throw and yields null forever, which the
 * detail screen renders as an indefinite spinner. Coaches may READ a related
 * mentee's goal; writes stay owner-only.
 */
class CoachGoalReadAccessTest extends TestCase
{
    use RefreshDatabase;

    private Company $company;
    private User $coach;
    private User $mentee;
    private Goal $goal;

    protected function setUp(): void
    {
        parent::setUp();

        $this->company = Company::create([
            'id' => (string) Str::uuid(),
            'name' => 'Abundance',
            'code' => 'ABU15DN',
        ]);

        $this->coach = User::factory()->create([
            'company_id' => $this->company->id,
            'active_company_id' => $this->company->id,
        ]);
        $this->mentee = User::factory()->create([
            'company_id' => $this->company->id,
            'active_company_id' => $this->company->id,
        ]);

        CoachMentee::create([
            'coach_id' => (string) $this->coach->id,
            'mentee_id' => (string) $this->mentee->id,
            'mentee_name' => 'Maychell Alcorin',
        ]);

        $this->goal = Goal::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $this->mentee->id,
            'company_id' => $this->company->id,
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
    }

    public function test_a_related_coach_can_read_all_five_goal_read_endpoints(): void
    {
        Sanctum::actingAs($this->coach);

        $this->getJson("/api/goals/{$this->goal->id}")
            ->assertOk()
            ->assertJsonPath('goal.title', 'Run 100 km');
        $this->getJson("/api/goals/{$this->goal->id}/tasks")->assertOk();
        $this->getJson("/api/goals/{$this->goal->id}/updates")->assertOk();
        $this->getJson("/api/goals/{$this->goal->id}/comments")->assertOk();
        $this->getJson("/api/goals/{$this->goal->id}/merits")->assertOk();
    }

    public function test_an_unrelated_coach_cannot_read_the_goal(): void
    {
        $unrelatedCoach = User::factory()->create([
            'company_id' => $this->company->id,
            'active_company_id' => $this->company->id,
        ]);
        Sanctum::actingAs($unrelatedCoach);

        $this->getJson("/api/goals/{$this->goal->id}")->assertUnauthorized();
        $this->getJson("/api/goals/{$this->goal->id}/tasks")->assertUnauthorized();
        $this->getJson("/api/goals/{$this->goal->id}/updates")->assertUnauthorized();
        $this->getJson("/api/goals/{$this->goal->id}/comments")->assertUnauthorized();
        $this->getJson("/api/goals/{$this->goal->id}/merits")->assertUnauthorized();
    }

    public function test_the_owner_can_still_read_their_own_goal(): void
    {
        Sanctum::actingAs($this->mentee);

        $this->getJson("/api/goals/{$this->goal->id}")
            ->assertOk()
            ->assertJsonPath('goal.title', 'Run 100 km');
    }

    public function test_a_related_coach_still_cannot_write_to_the_goal(): void
    {
        Sanctum::actingAs($this->coach);

        $this->patchJson("/api/goals/{$this->goal->id}", ['title' => 'Hijacked'])
            ->assertUnauthorized();
        $this->postJson("/api/goals/{$this->goal->id}/tasks", ['title' => 'New plan'])
            ->assertUnauthorized();
        $this->postJson("/api/goals/{$this->goal->id}/comments", ['body' => 'hi'])
            ->assertUnauthorized();
        $this->postJson("/api/goals/{$this->goal->id}/measure", ['currentValue' => 90])
            ->assertUnauthorized();
        $this->postJson("/api/goals/{$this->goal->id}/merits/target", [])
            ->assertUnauthorized();
        $this->postJson("/api/goals/{$this->goal->id}/merits/extra", ['amount' => 5])
            ->assertUnauthorized();
        $this->deleteJson("/api/goals/{$this->goal->id}")->assertUnauthorized();

        $this->assertSame('Run 100 km', $this->goal->fresh()->title);
    }
}
