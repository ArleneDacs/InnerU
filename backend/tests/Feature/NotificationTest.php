<?php

namespace Tests\Feature;

use App\Models\CoachMentee;
use App\Models\CoachRequest;
use App\Models\CommunityPost;
use App\Models\Notification;
use App\Models\TodoTask;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class NotificationTest extends TestCase
{
    use RefreshDatabase;

    public function test_create_for_produces_a_notification_row_with_the_right_shape(): void
    {
        $user = User::factory()->create();

        $notification = Notification::createFor(
            (string) $user->id,
            'streak_milestone',
            'Test title',
            'Test body',
            ['days' => 7],
        );

        $this->assertIsString($notification->id);
        $this->assertSame((string) $user->id, (string) $notification->user_id);
        $this->assertSame('streak_milestone', $notification->type);
        $this->assertSame('Test title', $notification->title);
        $this->assertSame('Test body', $notification->body);
        $this->assertSame(['days' => 7], $notification->data);
        $this->assertNull($notification->read_at);

        $this->assertDatabaseHas('notifications', [
            'id' => $notification->id,
            'user_id' => (string) $user->id,
            'type' => 'streak_milestone',
            'title' => 'Test title',
        ]);
    }

    public function test_index_returns_only_the_authenticated_users_notifications_with_unread_count(): void
    {
        $user = User::factory()->create();
        $otherUser = User::factory()->create();

        Notification::createFor((string) $user->id, 'community_comment', 'A');
        $readOne = Notification::createFor((string) $user->id, 'community_comment', 'B');
        $readOne->update(['read_at' => now()]);
        Notification::createFor((string) $otherUser->id, 'community_comment', 'Not mine');

        Sanctum::actingAs($user);

        $response = $this->getJson('/api/notifications');

        $response->assertOk()
            ->assertJsonPath('unreadCount', 1)
            ->assertJsonCount(2, 'notifications');

        $titles = collect($response->json('notifications'))->pluck('title');
        $this->assertTrue($titles->contains('A'));
        $this->assertTrue($titles->contains('B'));
        $this->assertFalse($titles->contains('Not mine'));
    }

    public function test_mark_read_marks_the_notification_read_and_rejects_marking_someone_elses(): void
    {
        $user = User::factory()->create();
        $otherUser = User::factory()->create();

        $mine = Notification::createFor((string) $user->id, 'community_comment', 'Mine');
        $theirs = Notification::createFor((string) $otherUser->id, 'community_comment', 'Theirs');

        Sanctum::actingAs($user);

        $markMine = $this->patchJson('/api/notifications/'.$mine->id.'/read');
        $markMine->assertOk();
        $this->assertNotNull($markMine->json('notification.readAt'));
        $this->assertNotNull($mine->fresh()->read_at);

        $markTheirs = $this->patchJson('/api/notifications/'.$theirs->id.'/read');
        $markTheirs->assertForbidden();
        $this->assertNull($theirs->fresh()->read_at);

        // Idempotent: marking an already-read notification again still succeeds.
        $markAgain = $this->patchJson('/api/notifications/'.$mine->id.'/read');
        $markAgain->assertOk();
    }

    public function test_mark_all_read_marks_every_unread_notification_for_the_user(): void
    {
        $user = User::factory()->create();

        $first = Notification::createFor((string) $user->id, 'community_comment', 'A');
        $second = Notification::createFor((string) $user->id, 'community_comment', 'B');

        Sanctum::actingAs($user);

        $response = $this->patchJson('/api/notifications/read-all');
        $response->assertOk();

        $this->assertNotNull($first->fresh()->read_at);
        $this->assertNotNull($second->fresh()->read_at);
    }

    public function test_streak_endpoint_only_ever_notifies_the_authenticated_user(): void
    {
        $user = User::factory()->create();
        $otherUser = User::factory()->create();

        Sanctum::actingAs($user);

        $response = $this->postJson('/api/notifications/streak', [
            'milestone' => '7-day meditation streak',
            'days' => 7,
            'activity' => 'meditation',
            'user_id' => (string) $otherUser->id, // attempted spoof, must be ignored
        ]);

        $response->assertCreated()
            ->assertJsonPath('notification.userId', (string) $user->id)
            ->assertJsonPath('notification.type', 'streak_milestone');

        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $user->id,
            'type' => 'streak_milestone',
        ]);
        $this->assertDatabaseMissing('notifications', [
            'user_id' => (string) $otherUser->id,
        ]);
    }

    public function test_accepting_a_mentee_request_notifies_the_mentee(): void
    {
        $coach = User::factory()->create([
            'name' => 'Coach Notify',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create(['name' => 'Mentee Notify']);

        CoachRequest::create([
            'id' => $mentee->id.'_'.$coach->id,
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
        ]);

        Sanctum::actingAs($coach);

        $accept = $this->patchJson('/api/coach/requests/'.$mentee->id.'_'.$coach->id.'/accept', [
            'team_name' => 'Core Team',
        ]);
        $accept->assertOk();

        $notification = Notification::query()
            ->where('user_id', (string) $mentee->id)
            ->where('type', 'mentee_request_accepted')
            ->first();

        $this->assertNotNull($notification);
        $this->assertStringContainsString('Coach Notify', $notification->title);
    }

    public function test_commenting_on_a_community_post_notifies_the_owner_but_not_when_commenting_on_your_own(): void
    {
        $owner = User::factory()->create(['name' => 'Post Owner']);
        $commenter = User::factory()->create(['name' => 'Commenter']);

        $post = CommunityPost::create([
            'user_id' => (string) $owner->id,
            'username' => $owner->name,
            'title' => 'A post',
            'note' => ['text' => 'hello'],
            'category' => 'General',
            'saved' => false,
        ]);

        Sanctum::actingAs($commenter);

        $comment = $this->postJson('/api/community/posts/'.$post->id.'/comments', [
            'comment' => 'Great post, really enjoyed it and learned a lot from it today!',
        ]);
        $comment->assertCreated();

        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $owner->id,
            'type' => 'community_comment',
        ]);

        // Self-comment: no notification.
        Notification::query()->delete();
        Sanctum::actingAs($owner);
        $selfComment = $this->postJson('/api/community/posts/'.$post->id.'/comments', [
            'comment' => 'Adding my own follow-up thought.',
        ]);
        $selfComment->assertCreated();

        $this->assertDatabaseMissing('notifications', [
            'user_id' => (string) $owner->id,
            'type' => 'community_comment',
        ]);
    }

    public function test_completing_a_todo_task_notifies_the_assigned_coach_but_only_on_the_completion_transition(): void
    {
        $coach = User::factory()->create([
            'name' => 'Todo Coach',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create(['name' => 'Todo Mentee']);

        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Team',
        ]);

        $task = TodoTask::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $mentee->id,
            'title' => 'Finish onboarding',
            'description' => '',
            'due_date' => now()->toDateString(),
            'tag' => 'none',
            'is_completed' => false,
            'sub_tasks' => [],
        ]);

        Sanctum::actingAs($mentee);

        $complete = $this->patchJson('/api/todo-tasks/'.$task->id, [
            'is_completed' => true,
        ]);
        $complete->assertOk();

        $this->assertSame(
            1,
            Notification::query()
                ->where('user_id', (string) $coach->id)
                ->where('type', 'mentee_progress_logged')
                ->count(),
        );

        // A second update that isn't a completion transition (already
        // completed, just editing the title) must not fire again.
        $editAgain = $this->patchJson('/api/todo-tasks/'.$task->id, [
            'title' => 'Finish onboarding v2',
        ]);
        $editAgain->assertOk();

        $this->assertSame(
            1,
            Notification::query()
                ->where('user_id', (string) $coach->id)
                ->where('type', 'mentee_progress_logged')
                ->count(),
        );
    }

    public function test_daily_tracker_notifies_the_assigned_coach_only_on_first_creation_for_the_day(): void
    {
        $coach = User::factory()->create([
            'name' => 'Tracker Coach',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create(['name' => 'Tracker Mentee']);

        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Team',
        ]);

        Sanctum::actingAs($mentee);

        $first = $this->postJson('/api/daily-tracker', [
            'date' => '2026-07-29',
            'meditation' => true,
        ]);
        $first->assertOk();

        $this->assertSame(
            1,
            Notification::query()
                ->where('user_id', (string) $coach->id)
                ->where('type', 'mentee_progress_logged')
                ->count(),
        );

        $second = $this->postJson('/api/daily-tracker', [
            'date' => '2026-07-29',
            'steps' => true,
        ]);
        $second->assertOk();

        $this->assertSame(
            1,
            Notification::query()
                ->where('user_id', (string) $coach->id)
                ->where('type', 'mentee_progress_logged')
                ->count(),
        );
    }
}
