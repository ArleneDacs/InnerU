<?php

namespace Tests\Feature;

use App\Models\CoachMentee;
use App\Models\DailyTracker;
use App\Models\Notification;
use App\Models\StepSubmission;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class StepSubmissionTest extends TestCase
{
    use RefreshDatabase;

    public function test_mentee_can_create_a_submission_and_their_coach_is_notified(): void
    {
        $coach = User::factory()->create([
            'name' => 'Coach One',
            'is_coach' => true,
            'role' => 'coach',
        ]);
        $mentee = User::factory()->create(['name' => 'Mentee One']);

        CoachMentee::create([
            'coach_id' => (string) $coach->id,
            'mentee_id' => (string) $mentee->id,
            'team_name' => 'Team',
        ]);

        Sanctum::actingAs($mentee);

        $response = $this->postJson('/api/step-submissions', [
            'steps' => 8000,
            'date' => '2026-07-29',
            'proof_url' => 'https://example.com/proof.jpg',
            'note' => 'Walked to the park and back.',
        ]);

        $response->assertCreated()
            ->assertJsonPath('submission.userId', (string) $mentee->id)
            ->assertJsonPath('submission.steps', 8000)
            ->assertJsonPath('submission.status', 'pending')
            ->assertJsonPath('submission.date', '2026-07-29');

        $this->assertDatabaseHas('step_submissions', [
            'user_id' => (string) $mentee->id,
            'steps' => 8000,
            'status' => 'pending',
        ]);

        $this->assertSame(
            1,
            Notification::query()
                ->where('user_id', (string) $coach->id)
                ->where('type', 'step_submission_received')
                ->count(),
        );
    }

    public function test_mentee_with_no_coach_can_still_submit_without_error_or_notification(): void
    {
        $mentee = User::factory()->create(['name' => 'Lone Mentee']);

        Sanctum::actingAs($mentee);

        $response = $this->postJson('/api/step-submissions', [
            'steps' => 5000,
            'date' => '2026-07-29',
            'proof_url' => 'https://example.com/proof.jpg',
        ]);

        $response->assertCreated();

        $this->assertDatabaseHas('step_submissions', [
            'user_id' => (string) $mentee->id,
            'steps' => 5000,
        ]);

        $this->assertSame(0, Notification::query()->where('type', 'step_submission_received')->count());
    }

    public function test_coach_queue_only_returns_their_own_mentees_submissions(): void
    {
        $coachA = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $coachB = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $menteeA = User::factory()->create(['name' => 'Mentee A']);
        $menteeB = User::factory()->create(['name' => 'Mentee B']);

        CoachMentee::create(['coach_id' => (string) $coachA->id, 'mentee_id' => (string) $menteeA->id]);
        CoachMentee::create(['coach_id' => (string) $coachB->id, 'mentee_id' => (string) $menteeB->id]);

        $submissionA = StepSubmission::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => (string) $menteeA->id,
            'steps' => 3000,
            'date' => '2026-07-29',
            'proof_url' => 'https://example.com/a.jpg',
            'status' => 'pending',
        ]);

        StepSubmission::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => (string) $menteeB->id,
            'steps' => 4000,
            'date' => '2026-07-29',
            'proof_url' => 'https://example.com/b.jpg',
            'status' => 'pending',
        ]);

        Sanctum::actingAs($coachA);

        $response = $this->getJson('/api/coach/step-submissions');
        $response->assertOk()->assertJsonCount(1, 'submissions');

        $ids = collect($response->json('submissions'))->pluck('id');
        $this->assertTrue($ids->contains($submissionA->id));

        $this->assertJsonPathEqualsMenteeName($response->json('submissions.0'), 'Mentee A');
    }

    public function test_approve_writes_the_daily_tracker_notifies_the_mentee_and_rejects_unrelated_coaches(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $otherCoach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create(['name' => 'Approved Mentee']);

        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id]);

        $submission = StepSubmission::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => (string) $mentee->id,
            'steps' => 9500,
            'date' => '2026-07-29',
            'proof_url' => 'https://example.com/proof.jpg',
            'status' => 'pending',
        ]);

        // A coach not assigned to this mentee must be rejected.
        Sanctum::actingAs($otherCoach);
        $forbidden = $this->patchJson('/api/coach/step-submissions/'.$submission->id.'/approve');
        $this->assertContains($forbidden->getStatusCode(), [401, 403]);
        $this->assertSame('pending', $submission->fresh()->status);

        Sanctum::actingAs($coach);
        $approve = $this->patchJson('/api/coach/step-submissions/'.$submission->id.'/approve');
        $approve->assertOk()->assertJsonPath('submission.status', 'approved');

        $this->assertDatabaseHas('daily_trackers', [
            'user_id' => (string) $mentee->id,
            'step_count' => 9500,
            'steps' => true,
        ]);

        $tracker = DailyTracker::query()
            ->where('user_id', (string) $mentee->id)
            ->whereDate('date', '2026-07-29')
            ->first();
        $this->assertNotNull($tracker);
        $this->assertSame(9500, $tracker->step_count);
        $this->assertTrue((bool) $tracker->steps);

        $this->assertSame(
            1,
            Notification::query()
                ->where('user_id', (string) $mentee->id)
                ->where('type', 'step_submission_approved')
                ->count(),
        );

        // Already reviewed: a second approve attempt must not silently
        // re-process.
        $again = $this->patchJson('/api/coach/step-submissions/'.$submission->id.'/approve');
        $again->assertStatus(422);
    }

    public function test_approve_does_not_lower_an_already_higher_tracked_step_count(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create(['name' => 'High Steps Mentee']);

        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id]);

        DailyTracker::create([
            'user_id' => (string) $mentee->id,
            'username' => $mentee->name,
            'date' => '2026-07-29',
            'step_count' => 12000,
            'step_goal' => 5000,
        ]);

        $submission = StepSubmission::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => (string) $mentee->id,
            'steps' => 6000,
            'date' => '2026-07-29',
            'proof_url' => 'https://example.com/proof.jpg',
            'status' => 'pending',
        ]);

        Sanctum::actingAs($coach);
        $approve = $this->patchJson('/api/coach/step-submissions/'.$submission->id.'/approve');
        $approve->assertOk();

        $tracker = DailyTracker::query()
            ->where('user_id', (string) $mentee->id)
            ->whereDate('date', '2026-07-29')
            ->first();

        $this->assertSame(12000, $tracker->step_count);
        $this->assertTrue((bool) $tracker->steps);
    }

    public function test_decline_requires_a_reason_and_does_not_touch_the_tracker(): void
    {
        $coach = User::factory()->create(['is_coach' => true, 'role' => 'coach']);
        $mentee = User::factory()->create(['name' => 'Declined Mentee']);

        CoachMentee::create(['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id]);

        $submission = StepSubmission::create([
            'id' => (string) \Illuminate\Support\Str::uuid(),
            'user_id' => (string) $mentee->id,
            'steps' => 4000,
            'date' => '2026-07-29',
            'proof_url' => 'https://example.com/proof.jpg',
            'status' => 'pending',
        ]);

        Sanctum::actingAs($coach);

        $noReason = $this->patchJson('/api/coach/step-submissions/'.$submission->id.'/decline', []);
        $noReason->assertStatus(422);
        $this->assertSame('pending', $submission->fresh()->status);

        $decline = $this->patchJson('/api/coach/step-submissions/'.$submission->id.'/decline', [
            'reason' => 'The photo does not match a step tracker screen.',
        ]);
        $decline->assertOk()
            ->assertJsonPath('submission.status', 'declined')
            ->assertJsonPath('submission.declineReason', 'The photo does not match a step tracker screen.');

        $this->assertDatabaseMissing('daily_trackers', [
            'user_id' => (string) $mentee->id,
        ]);

        $notification = Notification::query()
            ->where('user_id', (string) $mentee->id)
            ->where('type', 'step_submission_declined')
            ->first();
        $this->assertNotNull($notification);
        $this->assertSame('The photo does not match a step tracker screen.', $notification->body);

        // Already reviewed: a second decline attempt must not silently
        // re-process.
        $again = $this->patchJson('/api/coach/step-submissions/'.$submission->id.'/decline', [
            'reason' => 'Trying again.',
        ]);
        $again->assertStatus(422);
    }

    private function assertJsonPathEqualsMenteeName(array $row, string $expectedName): void
    {
        $this->assertSame($expectedName, $row['menteeName']);
    }
}
