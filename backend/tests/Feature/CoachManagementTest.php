<?php

namespace Tests\Feature;

use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\CoachRequest;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CoachManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_coach_can_manage_groups_and_mentees(): void
    {
        $coach = User::factory()->create([
            'name' => 'Coach One',
            'email' => 'coach@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create([
            'name' => 'Mentee One',
            'email' => 'mentee@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);

        Sanctum::actingAs($coach);

        $createGroup = $this->postJson('/api/coach/groups', [
            'name' => 'Morning Crew',
        ]);

        $createGroup->assertCreated()
            ->assertJsonPath('group.name', 'Morning Crew');

        $groupId = $createGroup->json('group.id');
        $this->assertIsString($groupId);

        $assign = $this->postJson('/api/coach/mentees/assign', [
            'mentee_id' => (string) $mentee->id,
            'mentee_name' => $mentee->name,
            'mentee_email' => $mentee->email,
            'team_name' => 'Morning Crew',
            'group_id' => $groupId,
            'group_name' => 'Morning Crew',
        ]);

        $assign->assertOk()
            ->assertJsonPath('mentee.menteeId', (string) $mentee->id)
            ->assertJsonPath('mentee.groupId', $groupId);

        $this->assertDatabaseHas('coach_groups', [
            'id' => $groupId,
            'coach_id' => (string) $coach->id,
            'name' => 'Morning Crew',
        ]);

        $this->assertDatabaseHas('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'group_id' => $groupId,
        ]);

        $groups = $this->getJson('/api/coach/groups');
        $groups->assertOk()
            ->assertJsonPath('groups.0.memberCount', 1);

        $remove = $this->deleteJson('/api/coach/mentees/'.$mentee->id);
        $remove->assertOk();

        $this->assertDatabaseMissing('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
        ]);
    }

    public function test_coach_can_accept_and_decline_requests(): void
    {
        $coach = User::factory()->create([
            'name' => 'Coach Two',
            'email' => 'coach2@example.com',
            'company_code' => 'XYZ',
            'company_name' => 'XYZ',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create([
            'name' => 'Mentee Two',
            'email' => 'mentee2@example.com',
            'company_code' => 'XYZ',
            'company_name' => 'XYZ',
        ]);

        CoachRequest::create([
            'id' => $mentee->id.'_'. $coach->id,
            'coach_id' => (string) $coach->id,
            'coach_name' => $coach->name,
            'coach_email' => $coach->email,
            'mentee_id' => (string) $mentee->id,
            'mentee_name' => $mentee->name,
            'mentee_email' => $mentee->email,
            'applicant_role' => 'user',
            'applicant_is_coach' => false,
            'applying_as' => 'mentee',
            'status' => 'pending',
            'company_code' => 'XYZ',
            'company_name' => 'XYZ',
        ]);

        Sanctum::actingAs($coach);

        $accept = $this->patchJson('/api/coach/requests/'.$mentee->id.'_'.$coach->id.'/accept', [
            'team_name' => 'Core Team',
        ]);
        $accept->assertOk()
            ->assertJsonPath('request.status', 'accepted');

        $this->assertDatabaseHas('coach_requests', [
            'id' => $mentee->id.'_'.$coach->id,
            'status' => 'accepted',
        ]);
        $this->assertDatabaseHas('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Core Team',
        ]);

        $decline = $this->patchJson('/api/coach/requests/'.$mentee->id.'_'.$coach->id.'/decline');
        $decline->assertOk()
            ->assertJsonPath('request.status', 'rejected');
    }
}
