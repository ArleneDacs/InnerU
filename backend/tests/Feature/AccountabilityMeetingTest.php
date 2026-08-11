<?php

namespace Tests\Feature;

use App\Models\AccountabilityMeeting;
use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\DailyTracker;
use App\Models\Notification;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AccountabilityMeetingTest extends TestCase
{
    use RefreshDatabase;

    private function makeGroup(User $coach, string $name = 'Morning Crew'): CoachGroup
    {
        return CoachGroup::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'company_id' => $coach->company_id,
            'coach_ids' => [(string) $coach->id],
            'name' => $name,
            'member_ids' => [],
            'member_count' => 0,
            'company_code' => $coach->company_code,
            'company_name' => $coach->company_name,
        ]);
    }

    public function test_a_coach_can_schedule_a_meeting_for_a_group_they_own(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $group = $this->makeGroup($coach);

        Sanctum::actingAs($coach);

        $response = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Weekly Check-in',
            'zoom_link' => 'https://zoom.us/j/123456789?pwd=abcDEF',
            'scheduled_at' => now()->addDays(2)->toIso8601String(),
            'notes' => 'Bring your goals sheet.',
        ]);

        $response->assertCreated()
            ->assertJsonPath('meeting.title', 'Weekly Check-in')
            ->assertJsonPath('meeting.groupId', $group->id)
            ->assertJsonPath('meeting.coachId', (string) $coach->id)
            ->assertJsonPath('meeting.zoomLink', 'https://zoom.us/j/123456789?pwd=abcDEF');

        $this->assertDatabaseHas('accountability_meetings', [
            'coach_id' => (string) $coach->id,
            'group_id' => $group->id,
            'title' => 'Weekly Check-in',
        ]);
    }

    public function test_a_coach_who_does_not_own_or_co_own_the_group_is_rejected(): void
    {
        $owningCoach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $outsideCoach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $group = $this->makeGroup($owningCoach);

        Sanctum::actingAs($outsideCoach);

        $response = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Weekly Check-in',
            'zoom_link' => 'https://zoom.us/j/123456789',
            'scheduled_at' => now()->addDays(2)->toIso8601String(),
        ]);

        $this->assertContains($response->getStatusCode(), [401, 403]);
        $this->assertDatabaseMissing('accountability_meetings', ['group_id' => $group->id]);
    }

    public function test_a_co_coach_listed_in_coach_ids_can_also_schedule_a_meeting(): void
    {
        $owningCoach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $coCoach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $group = CoachGroup::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $owningCoach->id,
            'coach_ids' => [(string) $owningCoach->id, (string) $coCoach->id],
            'name' => 'Shared Group',
        ]);

        Sanctum::actingAs($coCoach);

        $response = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Shared Sync',
            'zoom_link' => 'https://zoom.us/j/999',
            'scheduled_at' => now()->addDays(1)->toIso8601String(),
        ]);

        $response->assertCreated();
    }

    public function test_a_group_member_can_schedule_a_meeting_and_it_is_visible_to_peers_and_coaches(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $schedulingMember = User::factory()->create(['name' => 'Scheduling Member']);
        $peer = User::factory()->create(['name' => 'Group Peer']);
        $group = $this->makeGroup($coach);
        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $schedulingMember->id,
            'group_id' => $group->id,
        ]);
        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $peer->id,
            'group_id' => $group->id,
        ]);

        Sanctum::actingAs($schedulingMember);
        $created = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Member-led check-in',
            'zoom_link' => 'https://zoom.us/j/123456789?pwd=member',
            'scheduled_at' => now()->addDays(2)->toIso8601String(),
        ]);

        $created->assertCreated()
            ->assertJsonPath('meeting.coachId', (string) $schedulingMember->id)
            ->assertJsonPath('meeting.isCreator', true);

        Sanctum::actingAs($peer);
        $peerMeetings = $this->getJson('/api/accountability-meetings/mine');
        $peerMeetings->assertOk()
            ->assertJsonCount(1, 'meetings')
            ->assertJsonPath('meetings.0.title', 'Member-led check-in')
            ->assertJsonPath('meetings.0.isCreator', false);

        Sanctum::actingAs($coach);
        $coachMeetings = $this->getJson('/api/coach/accountability-meetings');
        $coachMeetings->assertOk()
            ->assertJsonCount(1, 'meetings')
            ->assertJsonPath('meetings.0.title', 'Member-led check-in')
            ->assertJsonPath('meetings.0.isCreator', false);

        // Coach reminder taps open the same member-facing list, so managed
        // groups must be visible and joinable there too.
        $coachMine = $this->getJson('/api/accountability-meetings/mine');
        $coachMine->assertOk()
            ->assertJsonCount(1, 'meetings')
            ->assertJsonPath('meetings.0.title', 'Member-led check-in');
        $this->postJson('/api/accountability-meetings/'.$created->json('meeting.id').'/join')
            ->assertOk()
            ->assertJsonPath('alreadyJoined', false);
    }

    public function test_group_member_can_list_only_their_schedulable_groups(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $member = User::factory()->create();
        $myGroup = $this->makeGroup($coach, 'My Group');
        $otherGroup = $this->makeGroup($coach, 'Other Group');
        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $member->id,
            'group_id' => $myGroup->id,
        ]);

        Sanctum::actingAs($member);
        $response = $this->getJson('/api/accountability-meetings/groups');

        $response->assertOk()
            ->assertJsonCount(1, 'groups')
            ->assertJsonPath('groups.0.id', $myGroup->id)
            ->assertJsonPath('groups.0.name', 'My Group');
        $response->assertJsonMissing(['id' => $otherGroup->id]);
    }

    public function test_a_user_outside_the_group_cannot_schedule_a_meeting_for_it(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $outsider = User::factory()->create();
        $group = $this->makeGroup($coach);

        Sanctum::actingAs($outsider);
        $response = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Unauthorized meeting',
            'zoom_link' => 'https://zoom.us/j/123456789',
            'scheduled_at' => now()->addDays(2)->toIso8601String(),
        ]);

        $response->assertForbidden();
        $this->assertDatabaseMissing('accountability_meetings', ['group_id' => $group->id]);
    }

    public function test_a_member_can_manage_only_the_meetings_they_created(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $creator = User::factory()->create();
        $peer = User::factory()->create();
        $group = $this->makeGroup($coach);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $creator->id, 'group_id' => $group->id]);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $peer->id, 'group_id' => $group->id]);

        Sanctum::actingAs($creator);
        $created = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Creator meeting',
            'zoom_link' => 'https://zoom.us/j/123456789',
            'scheduled_at' => now()->addDays(2)->toIso8601String(),
        ])->assertCreated();
        $meetingId = $created->json('meeting.id');

        $this->patchJson('/api/accountability-meetings/'.$meetingId, [
            'title' => 'Updated creator meeting',
            'zoom_link' => 'https://zoom.us/j/123456789',
            'scheduled_at' => now()->addDays(3)->toIso8601String(),
        ])->assertOk()->assertJsonPath('meeting.title', 'Updated creator meeting');

        Sanctum::actingAs($peer);
        $this->patchJson('/api/accountability-meetings/'.$meetingId, [
            'title' => 'Peer cannot edit',
            'zoom_link' => 'https://zoom.us/j/123456789',
            'scheduled_at' => now()->addDays(3)->toIso8601String(),
        ])->assertForbidden();
        $this->deleteJson('/api/accountability-meetings/'.$meetingId)->assertForbidden();

        $this->assertDatabaseHas('accountability_meetings', [
            'id' => $meetingId,
            'title' => 'Updated creator meeting',
        ]);
    }

    public function test_member_created_meeting_reminders_reach_each_group_member_and_coach_once(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $coCoach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $creator = User::factory()->create();
        $peer = User::factory()->create();
        $group = CoachGroup::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'coach_ids' => [(string) $coach->id, (string) $coCoach->id],
            'name' => 'Shared Group',
        ]);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $creator->id, 'group_id' => $group->id]);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $peer->id, 'group_id' => $group->id]);

        Sanctum::actingAs($creator);
        $created = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Tomorrow member meeting',
            'zoom_link' => 'https://zoom.us/j/999999',
            'scheduled_at' => now()->addDay()->toIso8601String(),
        ])->assertCreated();

        $this->assertSame(0, Notification::query()->where('type', 'meeting_reminder_day_before')->count());

        $this->artisan('meetings:sweep-reminders')->assertExitCode(0);

        foreach ([$creator, $peer, $coach, $coCoach] as $recipient) {
            $this->assertSame(
                1,
                Notification::query()
                    ->where('user_id', (string) $recipient->id)
                    ->where('type', 'meeting_reminder_day_before')
                    ->count(),
            );
        }

        $this->assertNotNull(
            AccountabilityMeeting::query()->find($created->json('meeting.id'))?->day_before_notified_at,
        );

        $this->artisan('meetings:sweep-reminders')->assertExitCode(0);
        $this->assertSame(4, Notification::query()->where('type', 'meeting_reminder_day_before')->count());
    }

    public function test_scheduled_at_in_the_past_is_rejected(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $group = $this->makeGroup($coach);

        Sanctum::actingAs($coach);

        $response = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Too Late',
            'zoom_link' => 'https://zoom.us/j/123456789',
            'scheduled_at' => now()->subDay()->toIso8601String(),
        ]);

        $response->assertStatus(422);
    }

    public function test_no_notifications_are_created_at_store_time(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create();
        $group = $this->makeGroup($coach);
        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'group_id' => $group->id,
        ]);

        Sanctum::actingAs($coach);

        $before = Notification::count();

        $response = $this->postJson('/api/accountability-meetings', [
            'group_id' => $group->id,
            'title' => 'Weekly Check-in',
            'zoom_link' => 'https://zoom.us/j/123456789',
            // Tomorrow, which is exactly the "day before" reminder window —
            // proves store() itself never notifies even when the sweep
            // would immediately be due.
            'scheduled_at' => now()->addDay()->toIso8601String(),
        ]);

        $response->assertCreated();
        $this->assertSame($before, Notification::count());
    }

    public function test_sweep_sends_day_before_reminders_and_is_idempotent(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $menteeA = User::factory()->create();
        $menteeB = User::factory()->create();
        $group = $this->makeGroup($coach);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $menteeA->id, 'group_id' => $group->id]);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $menteeB->id, 'group_id' => $group->id]);

        $meeting = AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'group_id' => $group->id,
            'title' => 'Tomorrow Meeting',
            'zoom_link' => 'https://zoom.us/j/123',
            'scheduled_at' => now()->addDay(),
        ]);

        $this->artisan('meetings:sweep-reminders')->assertExitCode(0);

        $this->assertSame(
            1,
            Notification::query()->where('user_id', (string) $menteeA->id)->where('type', 'meeting_reminder_day_before')->count(),
        );
        $this->assertSame(
            1,
            Notification::query()->where('user_id', (string) $menteeB->id)->where('type', 'meeting_reminder_day_before')->count(),
        );
        $this->assertNotNull($meeting->fresh()->day_before_notified_at);

        // Idempotency: running the sweep again must not double-notify.
        $this->artisan('meetings:sweep-reminders')->assertExitCode(0);

        $this->assertSame(
            1,
            Notification::query()->where('user_id', (string) $menteeA->id)->where('type', 'meeting_reminder_day_before')->count(),
        );
    }

    public function test_sweep_sends_day_of_reminders_and_is_idempotent(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create();
        $group = $this->makeGroup($coach);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id, 'group_id' => $group->id]);

        $meeting = AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'group_id' => $group->id,
            'title' => 'Today Meeting',
            'zoom_link' => 'https://zoom.us/j/456',
            'scheduled_at' => now()->addHours(2),
        ]);

        $this->artisan('meetings:sweep-reminders')->assertExitCode(0);

        $this->assertSame(
            1,
            Notification::query()->where('user_id', (string) $mentee->id)->where('type', 'meeting_reminder_day_of')->count(),
        );
        $this->assertNotNull($meeting->fresh()->day_of_notified_at);

        $this->artisan('meetings:sweep-reminders')->assertExitCode(0);

        $this->assertSame(
            1,
            Notification::query()->where('user_id', (string) $mentee->id)->where('type', 'meeting_reminder_day_of')->count(),
        );
    }

    public function test_a_meeting_far_in_the_future_gets_no_reminder_yet(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create();
        $group = $this->makeGroup($coach);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id, 'group_id' => $group->id]);

        $meeting = AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'group_id' => $group->id,
            'title' => 'Far Future Meeting',
            'zoom_link' => 'https://zoom.us/j/789',
            'scheduled_at' => now()->addDays(3),
        ]);

        $this->artisan('meetings:sweep-reminders')->assertExitCode(0);

        $this->assertSame(0, Notification::query()->where('type', 'meeting_reminder_day_before')->count());
        $this->assertSame(0, Notification::query()->where('type', 'meeting_reminder_day_of')->count());
        $this->assertNull($meeting->fresh()->day_before_notified_at);
        $this->assertNull($meeting->fresh()->day_of_notified_at);
    }

    public function test_index_opportunistically_triggers_the_sweep(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create();
        $group = $this->makeGroup($coach);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id, 'group_id' => $group->id]);

        $meeting = AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'group_id' => $group->id,
            'title' => 'Today Meeting',
            'zoom_link' => 'https://zoom.us/j/456',
            'scheduled_at' => now()->addHours(1),
        ]);

        Sanctum::actingAs($coach);
        $response = $this->getJson('/api/coach/accountability-meetings');

        $response->assertOk()->assertJsonPath('meetings.0.title', 'Today Meeting');
        $this->assertNotNull($meeting->fresh()->day_of_notified_at);
        $this->assertSame(
            1,
            Notification::query()->where('user_id', (string) $mentee->id)->where('type', 'meeting_reminder_day_of')->count(),
        );
    }

    public function test_mine_only_returns_meetings_for_groups_the_mentee_belongs_to(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create();
        $outsider = User::factory()->create();

        $myGroup = $this->makeGroup($coach, 'My Group');
        $otherGroup = $this->makeGroup($coach, 'Other Group');

        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id, 'group_id' => $myGroup->id]);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $outsider->id, 'group_id' => $otherGroup->id]);

        AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'group_id' => $myGroup->id,
            'title' => 'My Meeting',
            'zoom_link' => 'https://zoom.us/j/1',
            'scheduled_at' => now()->addDays(5),
        ]);
        AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'group_id' => $otherGroup->id,
            'title' => 'Other Meeting',
            'zoom_link' => 'https://zoom.us/j/2',
            'scheduled_at' => now()->addDays(5),
        ]);

        Sanctum::actingAs($mentee);
        $response = $this->getJson('/api/accountability-meetings/mine');

        $response->assertOk()->assertJsonCount(1, 'meetings')
            ->assertJsonPath('meetings.0.title', 'My Meeting');
    }

    public function test_a_mentee_in_the_group_can_join_and_it_updates_the_daily_tracker_without_clobbering_other_fields(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create(['name' => 'Joining Mentee']);
        $group = $this->makeGroup($coach);
        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id, 'group_id' => $group->id]);

        DailyTracker::create([
            'user_id' => (string) $mentee->id,
            'username' => $mentee->name,
            'date' => now()->toDateString(),
            'steps' => true,
            'step_count' => 4000,
        ]);

        $meeting = AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'group_id' => $group->id,
            'title' => 'Join Test Meeting',
            'zoom_link' => 'https://zoom.us/j/321',
            'scheduled_at' => now()->addHours(1),
        ]);

        Sanctum::actingAs($mentee);

        $response = $this->postJson('/api/accountability-meetings/'.$meeting->id.'/join');

        $response->assertOk()
            ->assertJsonPath('zoomLink', 'https://zoom.us/j/321')
            ->assertJsonPath('alreadyJoined', false);

        $tracker = DailyTracker::query()
            ->where('user_id', (string) $mentee->id)
            ->whereDate('date', now()->toDateString())
            ->first();

        $this->assertNotNull($tracker);
        $this->assertTrue((bool) $tracker->call);
        $this->assertSame(1, $tracker->call_count);
        // Other fields set before the join must be preserved, not clobbered.
        $this->assertTrue((bool) $tracker->steps);
        $this->assertSame(4000, $tracker->step_count);

        $this->assertDatabaseCount('meeting_attendances', 1);

        // A second join is idempotent: no duplicate attendance row, no
        // double-increment of call_count.
        $second = $this->postJson('/api/accountability-meetings/'.$meeting->id.'/join');
        $second->assertOk()->assertJsonPath('alreadyJoined', true);

        $this->assertDatabaseCount('meeting_attendances', 1);

        $trackerAfterSecondJoin = DailyTracker::query()
            ->where('user_id', (string) $mentee->id)
            ->whereDate('date', now()->toDateString())
            ->first();
        $this->assertSame(1, $trackerAfterSecondJoin->call_count);
    }

    public function test_a_mentee_not_in_the_group_cannot_join(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $group = $this->makeGroup($coach);
        $outsider = User::factory()->create();

        $meeting = AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $coach->id,
            'group_id' => $group->id,
            'title' => 'Locked Meeting',
            'zoom_link' => 'https://zoom.us/j/654',
            'scheduled_at' => now()->addHours(1),
        ]);

        Sanctum::actingAs($outsider);
        $response = $this->postJson('/api/accountability-meetings/'.$meeting->id.'/join');

        $this->assertContains($response->getStatusCode(), [401, 403]);
        $this->assertDatabaseCount('meeting_attendances', 0);
    }

    public function test_joining_a_nonexistent_meeting_returns_404(): void
    {
        $mentee = User::factory()->create();
        Sanctum::actingAs($mentee);

        $response = $this->postJson('/api/accountability-meetings/'.((string) Str::uuid()).'/join');

        $response->assertStatus(404);
    }
}
