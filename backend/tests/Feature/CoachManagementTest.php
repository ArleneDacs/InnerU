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

    public function test_creating_a_group_stamps_the_coachs_own_company_id(): void
    {
        $coach = User::factory()->create([
            'name' => 'Coach Company',
            'email' => 'coachcompany@example.com',
            'company_id' => 'company-uuid-123',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
            'is_coach' => true,
            'role' => 'coach',
        ]);

        Sanctum::actingAs($coach);

        $createGroup = $this->postJson('/api/coach/groups', [
            'name' => 'Stamped Group',
        ]);

        $createGroup->assertCreated();
        $groupId = $createGroup->json('group.id');

        $this->assertDatabaseHas('coach_groups', [
            'id' => $groupId,
            'company_id' => 'company-uuid-123',
        ]);
    }

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

    public function test_coach_directory_includes_coaches_from_other_companies(): void
    {
        $user = User::factory()->create([
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);
        $sameCompanyCoach = User::factory()->create([
            'name' => 'Same Company Coach',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $otherCompanyCoach = User::factory()->create([
            'name' => 'Other Company Coach',
            'company_code' => 'XYZ',
            'company_name' => 'XYZ',
            'is_coach' => true,
            'role' => 'coach',
        ]);

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/coaches');

        $response->assertOk();
        $ids = collect($response->json('coaches'))->pluck('id');

        $this->assertTrue($ids->contains((string) $sameCompanyCoach->id));
        $this->assertTrue($ids->contains((string) $otherCompanyCoach->id));
    }

    public function test_mentee_can_see_their_own_assigned_coaches(): void
    {
        $coachOne = User::factory()->create([
            'name' => 'Coach Alpha',
            'email' => 'alpha@example.com',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $coachTwo = User::factory()->create([
            'name' => 'Coach Beta',
            'email' => 'beta@example.com',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create([
            'name' => 'Mentee Four',
            'email' => 'mentee4@example.com',
        ]);

        CoachMentee::create([
            'coach_id' => (string) $coachOne->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Team A',
        ]);
        CoachMentee::create([
            'coach_id' => (string) $coachTwo->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Team B',
        ]);

        Sanctum::actingAs($mentee);

        $response = $this->getJson('/api/coach/my-coaches');

        $response->assertOk();
        $ids = collect($response->json('coaches'))->pluck('id');

        $this->assertSame(
            [(string) $coachOne->id, (string) $coachTwo->id],
            $ids->all(),
        );
    }

    public function test_mentee_with_no_coach_sees_an_empty_list(): void
    {
        $mentee = User::factory()->create([
            'name' => 'Mentee Five',
            'email' => 'mentee5@example.com',
        ]);

        Sanctum::actingAs($mentee);

        $response = $this->getJson('/api/coach/my-coaches');

        $response->assertOk()
            ->assertJson(['coaches' => []]);
    }

    public function test_coach_can_list_company_users_to_add_as_mentees(): void
    {
        $coach = User::factory()->create([
            'name' => 'Coach Three',
            'email' => 'coach3@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $sameCompanyUser = User::factory()->create([
            'name' => 'Mentee Three',
            'email' => 'mentee3@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);
        $otherCompanyUser = User::factory()->create([
            'name' => 'Outsider',
            'email' => 'outsider@example.com',
            'company_code' => 'XYZ',
            'company_name' => 'XYZ',
        ]);

        Sanctum::actingAs($coach);

        $response = $this->getJson('/api/coach/users');

        $response->assertOk();
        $ids = collect($response->json('users'))->pluck('id');

        $this->assertTrue($ids->contains((string) $sameCompanyUser->id));
        $this->assertFalse($ids->contains((string) $otherCompanyUser->id));
        $this->assertFalse($ids->contains((string) $coach->id));
    }

    public function test_coach_can_see_an_assigned_mentees_todo_tasks(): void
    {
        $coach = User::factory()->create([
            'name' => 'Coach Todo',
            'email' => 'coachtodo@example.com',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create([
            'name' => 'Mentee Todo',
            'email' => 'menteetodo@example.com',
        ]);

        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Team Todo',
        ]);

        \App\Models\TodoTask::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => (string) $mentee->id,
            'title' => 'Finish reading',
            'due_date' => now()->toDateString(),
            'is_completed' => true,
        ]);
        \App\Models\TodoTask::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => (string) $mentee->id,
            'title' => 'Log meals',
            'due_date' => now()->toDateString(),
            'is_completed' => false,
        ]);

        Sanctum::actingAs($coach);

        $response = $this->getJson("/api/coach/mentees/{$mentee->id}/todo-tasks");

        $response->assertOk();
        $tasks = collect($response->json('tasks'));

        $this->assertCount(2, $tasks);
        $this->assertTrue($tasks->firstWhere('title', 'Finish reading')['isCompleted']);
        $this->assertFalse($tasks->firstWhere('title', 'Log meals')['isCompleted']);
    }

    public function test_coach_cannot_see_todo_tasks_of_a_non_mentee(): void
    {
        $coach = User::factory()->create([
            'name' => 'Coach Stranger',
            'email' => 'coachstranger@example.com',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $unrelatedUser = User::factory()->create([
            'name' => 'Unrelated User',
            'email' => 'unrelated@example.com',
        ]);

        Sanctum::actingAs($coach);

        $response = $this->getJson("/api/coach/mentees/{$unrelatedUser->id}/todo-tasks");

        $response->assertStatus(401);
    }

    public function test_coach_can_rename_a_group_they_manage(): void
    {
        $coach = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);

        $group = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => 'Original Name',
            'photo_url' => 'https://example.com/original.png',
            'member_ids' => [],
            'member_count' => 0,
        ]);

        Sanctum::actingAs($coach);

        $response = $this->patchJson('/api/coach/groups/'.$group->id, [
            'name' => 'Renamed Group',
        ]);

        $response->assertOk()
            ->assertJsonPath('group.name', 'Renamed Group')
            ->assertJsonPath('group.photoUrl', 'https://example.com/original.png');

        $this->assertDatabaseHas('coach_groups', [
            'id' => $group->id,
            'name' => 'Renamed Group',
            'photo_url' => 'https://example.com/original.png',
        ]);
    }

    public function test_coach_can_set_group_photo_without_changing_name(): void
    {
        $coach = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);

        $group = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => 'Untouched Name',
            'member_ids' => [],
            'member_count' => 0,
        ]);

        Sanctum::actingAs($coach);

        $response = $this->patchJson('/api/coach/groups/'.$group->id, [
            'photo_url' => 'https://example.com/new-photo.png',
        ]);

        $response->assertOk()
            ->assertJsonPath('group.name', 'Untouched Name')
            ->assertJsonPath('group.photoUrl', 'https://example.com/new-photo.png');

        $this->assertDatabaseHas('coach_groups', [
            'id' => $group->id,
            'name' => 'Untouched Name',
            'photo_url' => 'https://example.com/new-photo.png',
        ]);
    }

    public function test_unrelated_coach_cannot_update_a_group(): void
    {
        $owner = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $stranger = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);

        $group = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $owner->id,
            'coach_ids' => [(string) $owner->id],
            'name' => 'Guarded Group',
            'member_ids' => [],
            'member_count' => 0,
        ]);

        Sanctum::actingAs($stranger);

        $response = $this->patchJson('/api/coach/groups/'.$group->id, [
            'name' => 'Hijacked Name',
        ]);

        $response->assertStatus(401);

        $this->assertDatabaseHas('coach_groups', [
            'id' => $group->id,
            'name' => 'Guarded Group',
        ]);
    }

    public function test_updating_a_group_without_name_or_photo_fails_validation(): void
    {
        $coach = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);

        $group = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => 'Untouched',
            'member_ids' => [],
            'member_count' => 0,
        ]);

        Sanctum::actingAs($coach);

        $response = $this->patchJson('/api/coach/groups/'.$group->id, []);

        $response->assertStatus(422);
    }

    public function test_removing_a_mentee_from_a_group_ungroups_but_keeps_the_mentee_relation(): void
    {
        $coach = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create();

        $group = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => 'Removal Group',
            'member_ids' => [],
            'member_count' => 1,
        ]);

        $relation = CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Removal Group',
            'group_id' => $group->id,
            'group_name' => $group->name,
        ]);

        Sanctum::actingAs($coach);

        $response = $this->postJson('/api/coach/groups/'.$group->id.'/remove-mentee', [
            'mentee_id' => (string) $mentee->id,
        ]);

        $response->assertOk()
            ->assertJsonPath('message', 'Removed from group.');

        $this->assertDatabaseHas('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'group_id' => null,
            'group_name' => null,
        ]);

        // Still a mentee of this coach -- just ungrouped.
        $mentees = $this->getJson('/api/coach/mentees');
        $mentees->assertOk();
        $menteeEntry = collect($mentees->json('mentees'))
            ->firstWhere('menteeId', (string) $mentee->id);
        $this->assertNotNull($menteeEntry);
        $this->assertNull($menteeEntry['groupId']);

        $groups = $this->getJson('/api/coach/groups');
        $groups->assertOk()
            ->assertJsonPath('groups.0.memberCount', 0)
            ->assertJsonPath('groups.0.memberIds', []);

        $this->assertDatabaseHas('coach_groups', [
            'id' => $group->id,
            'member_count' => 0,
        ]);
    }

    public function test_removing_a_mentee_not_in_the_group_returns_404_and_makes_no_changes(): void
    {
        $coach = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $otherCoach = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $menteeInOtherGroup = User::factory()->create();
        $unaffiliatedMentee = User::factory()->create();

        $group = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => 'Target Group',
            'member_ids' => [],
            'member_count' => 0,
        ]);

        $otherGroup = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => 'Other Group',
            'member_ids' => [],
            'member_count' => 1,
        ]);

        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $menteeInOtherGroup->id,
            'team_name' => 'Other Group',
            'group_id' => $otherGroup->id,
            'group_name' => $otherGroup->name,
        ]);

        Sanctum::actingAs($coach);

        // Mentee belongs to a different group of the same coach.
        $responseA = $this->postJson('/api/coach/groups/'.$group->id.'/remove-mentee', [
            'mentee_id' => (string) $menteeInOtherGroup->id,
        ]);
        $responseA->assertStatus(404);

        // Mentee is not a mentee of this coach at all.
        $responseB = $this->postJson('/api/coach/groups/'.$group->id.'/remove-mentee', [
            'mentee_id' => (string) $unaffiliatedMentee->id,
        ]);
        $responseB->assertStatus(404);

        $this->assertDatabaseHas('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $menteeInOtherGroup->id,
            'group_id' => $otherGroup->id,
        ]);
        $this->assertDatabaseHas('coach_groups', [
            'id' => $otherGroup->id,
            'member_count' => 1,
        ]);
    }

    public function test_unrelated_coach_cannot_remove_a_mentee_from_a_group_they_dont_manage(): void
    {
        $owner = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $stranger = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create();

        $group = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $owner->id,
            'coach_ids' => [(string) $owner->id],
            'name' => 'Owned Group',
            'member_ids' => [],
            'member_count' => 1,
        ]);

        CoachMentee::create([
            'coach_id' => (string) $owner->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Owned Group',
            'group_id' => $group->id,
            'group_name' => $group->name,
        ]);

        Sanctum::actingAs($stranger);

        $response = $this->postJson('/api/coach/groups/'.$group->id.'/remove-mentee', [
            'mentee_id' => (string) $mentee->id,
        ]);

        $response->assertStatus(401);

        $this->assertDatabaseHas('coach_mentees', [
            'coach_id' => (string) $owner->id,
            'mentee_id' => (string) $mentee->id,
            'group_id' => $group->id,
        ]);
    }

    public function test_coach_can_add_a_mentee_to_multiple_of_their_own_groups_simultaneously(): void
    {
        $coach = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create([
            'name' => 'Multi Group Mentee',
            'email' => 'multigroup@example.com',
        ]);

        $groupA = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => 'Group A',
            'member_ids' => [],
            'member_count' => 0,
        ]);
        $groupB = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id],
            'name' => 'Group B',
            'member_ids' => [],
            'member_count' => 0,
        ]);

        Sanctum::actingAs($coach);

        // Assign the same mentee to Group A, then Group B -- previously
        // this second call would have silently MOVED the mentee out of
        // Group A instead of also adding them to Group B.
        $assignA = $this->postJson('/api/coach/mentees/assign', [
            'mentee_id' => (string) $mentee->id,
            'mentee_name' => $mentee->name,
            'mentee_email' => $mentee->email,
            'team_name' => 'Team',
            'group_id' => $groupA->id,
            'group_name' => 'Group A',
        ]);
        $assignA->assertOk()->assertJsonPath('mentee.groupId', $groupA->id);

        $assignB = $this->postJson('/api/coach/mentees/assign', [
            'mentee_id' => (string) $mentee->id,
            'mentee_name' => $mentee->name,
            'mentee_email' => $mentee->email,
            'team_name' => 'Team',
            'group_id' => $groupB->id,
            'group_name' => 'Group B',
        ]);
        $assignB->assertOk()->assertJsonPath('mentee.groupId', $groupB->id);

        // Both memberships persist as independent rows.
        $this->assertDatabaseHas('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'group_id' => $groupA->id,
        ]);
        $this->assertDatabaseHas('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'group_id' => $groupB->id,
        ]);
        $this->assertSame(2, CoachMentee::query()
            ->where('coach_id', (string) $coach->id)
            ->where('mentee_id', (string) $mentee->id)
            ->count());

        // member_count is accurate on both groups.
        $groups = $this->getJson('/api/coach/groups');
        $groups->assertOk();
        $groupPayloads = collect($groups->json('groups'))->keyBy('id');
        $this->assertSame(1, $groupPayloads[$groupA->id]['memberCount']);
        $this->assertSame(1, $groupPayloads[$groupB->id]['memberCount']);
        $this->assertContains((string) $mentee->id, $groupPayloads[$groupA->id]['memberIds']);
        $this->assertContains((string) $mentee->id, $groupPayloads[$groupB->id]['memberIds']);

        $this->assertDatabaseHas('coach_groups', ['id' => $groupA->id, 'member_count' => 1]);
        $this->assertDatabaseHas('coach_groups', ['id' => $groupB->id, 'member_count' => 1]);

        // The mentee roster shows the mentee once, listing both groups.
        $mentees = $this->getJson('/api/coach/mentees');
        $mentees->assertOk();
        $menteeEntries = collect($mentees->json('mentees'))
            ->where('menteeId', (string) $mentee->id);
        $this->assertCount(1, $menteeEntries);
        $groupIds = $menteeEntries->first()['groupIds'];
        $this->assertContains($groupA->id, $groupIds);
        $this->assertContains($groupB->id, $groupIds);

        // Removing from Group A does not remove the mentee from Group B.
        $removeFromA = $this->postJson('/api/coach/groups/'.$groupA->id.'/remove-mentee', [
            'mentee_id' => (string) $mentee->id,
        ]);
        $removeFromA->assertOk();

        $this->assertDatabaseMissing('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'group_id' => $groupA->id,
        ]);
        $this->assertDatabaseHas('coach_mentees', [
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'group_id' => $groupB->id,
        ]);

        $groupsAfter = $this->getJson('/api/coach/groups');
        $groupsAfter->assertOk();
        $groupPayloadsAfter = collect($groupsAfter->json('groups'))->keyBy('id');
        $this->assertSame(0, $groupPayloadsAfter[$groupA->id]['memberCount']);
        $this->assertSame(1, $groupPayloadsAfter[$groupB->id]['memberCount']);
        $this->assertDatabaseHas('coach_groups', ['id' => $groupA->id, 'member_count' => 0]);
        $this->assertDatabaseHas('coach_groups', ['id' => $groupB->id, 'member_count' => 1]);

        // The mentee is still my mentee overall (via the Group B row).
        $menteesAfter = $this->getJson('/api/coach/mentees');
        $menteesAfter->assertOk();
        $menteeEntryAfter = collect($menteesAfter->json('mentees'))
            ->firstWhere('menteeId', (string) $mentee->id);
        $this->assertNotNull($menteeEntryAfter);
        $this->assertSame([$groupB->id], $menteeEntryAfter['groupIds']);
    }

    public function test_update_group_coaches_removes_omitted_co_coach_but_keeps_owner(): void
    {
        $owner = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $coCoach = User::factory()->create([
            'is_coach' => true,
            'role' => 'coach',
        ]);

        $group = CoachGroup::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'coach_id' => (string) $owner->id,
            'coach_ids' => [(string) $owner->id, (string) $coCoach->id],
            'name' => 'Two Coach Group',
            'member_ids' => [],
            'member_count' => 0,
        ]);

        Sanctum::actingAs($owner);

        // Submit a coach_ids list that omits the co-coach -- they should be removed.
        $response = $this->patchJson('/api/coach/groups/'.$group->id.'/coaches', [
            'coach_ids' => [(string) $owner->id],
        ]);

        $response->assertOk();
        $coachIds = collect($response->json('group.coachIds'));
        $this->assertTrue($coachIds->contains((string) $owner->id));
        $this->assertFalse($coachIds->contains((string) $coCoach->id));

        // Submit a coach_ids list that omits the owner -- the owner should
        // still be force-included in the result.
        $response2 = $this->patchJson('/api/coach/groups/'.$group->id.'/coaches', [
            'coach_ids' => [(string) $coCoach->id],
        ]);

        $response2->assertOk();
        $coachIds2 = collect($response2->json('group.coachIds'));
        $this->assertTrue($coachIds2->contains((string) $owner->id));
        $this->assertTrue($coachIds2->contains((string) $coCoach->id));
    }
}
