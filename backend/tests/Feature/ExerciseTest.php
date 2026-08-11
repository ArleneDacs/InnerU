<?php

namespace Tests\Feature;

use App\Models\ExerciseLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class ExerciseTest extends TestCase
{
    use RefreshDatabase;

    #[DataProvider('canonicalDurationProvider')]
    public function test_duration_seconds_is_the_canonical_exercise_duration(
        int $durationMinutes,
        int $durationSeconds,
    ): void {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/exercise', [
            'type' => 'Run',
            'duration_minutes' => $durationMinutes,
            'duration_seconds' => $durationSeconds,
            'intensity' => 2,
            'date' => '2026-08-11',
        ]);

        $response->assertCreated()
            ->assertJsonPath('log.durationMinutes', $durationMinutes)
            ->assertJsonPath('log.durationSeconds', $durationSeconds);

        $this->assertDatabaseHas('exercise_logs', [
            'user_id' => $user->id,
            'duration_minutes' => $durationMinutes,
            'duration_seconds' => $durationSeconds,
        ]);

        // Daily totals remain derived from the same canonical seconds value,
        // so this change cannot inflate activity/medal-related aggregates.
        $this->assertDatabaseHas('daily_trackers', [
            'user_id' => $user->id,
            'date' => '2026-08-11',
            'exercise_minutes' => $durationMinutes,
        ]);
    }

    /**
     * @return array<string, array{int, int}>
     */
    public static function canonicalDurationProvider(): array
    {
        return [
            '30 minutes' => [30, 30 * 60],
            '1 hour' => [60, 60 * 60],
            '2 hours' => [120, 2 * 60 * 60],
            '24-hour recovery cap' => [24 * 60, 24 * 60 * 60],
        ];
    }

    public function test_legacy_minutes_only_payload_derives_canonical_seconds(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/exercise', [
            'type' => 'Yoga',
            'duration_minutes' => 30,
            'intensity' => 2,
            'date' => '2026-08-11',
        ]);

        $response->assertCreated()
            ->assertJsonPath('log.durationMinutes', 30)
            ->assertJsonPath('log.durationSeconds', 1_800);

        $this->assertDatabaseHas('exercise_logs', [
            'user_id' => $user->id,
            'duration_minutes' => 30,
            'duration_seconds' => 1_800,
        ]);
    }

    public function test_seconds_win_when_a_legacy_minutes_value_disagrees(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/exercise', [
            'type' => 'Cycling',
            'duration_minutes' => 120,
            'duration_seconds' => 3_600,
            'intensity' => 3,
            'date' => '2026-08-11',
        ]);

        $response->assertCreated()
            ->assertJsonPath('log.durationMinutes', 60)
            ->assertJsonPath('log.durationSeconds', 3_600);

        $this->assertDatabaseHas('exercise_logs', [
            'user_id' => $user->id,
            'duration_minutes' => 60,
            'duration_seconds' => 3_600,
        ]);
    }

    #[DataProvider('overLimitDurationProvider')]
    public function test_rejects_stale_or_long_exercise_sessions(
        string $durationField,
        int $duration,
    ): void {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/exercise', [
            'type' => 'Walk',
            $durationField => $duration,
            'intensity' => 1,
        ]);

        $response->assertUnprocessable()
            ->assertJsonValidationErrors([$durationField]);

        $this->assertDatabaseCount('exercise_logs', 0);
        $this->assertDatabaseCount('daily_trackers', 0);
    }

    /**
     * @return array<string, array{string, int}>
     */
    public static function overLimitDurationProvider(): array
    {
        return [
            'seconds over 24 hours' => ['duration_seconds', 86_401],
            'legacy minutes over 24 hours' => ['duration_minutes', 1_441],
        ];
    }

    public function test_user_can_create_list_and_delete_exercise_logs(): void
    {
        $user = User::factory()->create([
            'name' => 'Exercise User',
            'email' => 'exercise@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);

        Sanctum::actingAs($user);

        $create = $this->postJson('/api/exercise', [
            'type' => 'Yoga',
            'duration_minutes' => 45,
            'duration_seconds' => 2700,
            'intensity' => 2,
            'notes' => 'Morning flow',
            'date' => '2026-07-21',
        ]);

        $create->assertCreated()
            ->assertJsonPath('log.type', 'Yoga')
            ->assertJsonPath('log.durationMinutes', 45)
            ->assertJsonPath('log.durationSeconds', 2700);

        $secondCreate = $this->postJson('/api/exercise', [
            'type' => 'Walk',
            'duration_minutes' => 2,
            'duration_seconds' => 90,
            'intensity' => 1,
            'notes' => 'Afternoon cooldown',
            'date' => '2026-07-22',
        ]);

        $secondCreate->assertCreated()
            ->assertJsonPath('log.type', 'Walk')
            ->assertJsonPath('log.durationMinutes', 2)
            ->assertJsonPath('log.durationSeconds', 90);

        $this->assertDatabaseHas('exercise_logs', [
            'user_id' => $user->id,
            'type' => 'Yoga',
            'duration_minutes' => 45,
            'duration_seconds' => 2700,
        ]);

        $this->assertDatabaseHas('exercise_logs', [
            'user_id' => $user->id,
            'type' => 'Walk',
            'duration_minutes' => 2,
            'duration_seconds' => 90,
        ]);

        $this->assertDatabaseHas('daily_trackers', [
            'user_id' => $user->id,
            'date' => '2026-07-21',
            'exercise' => true,
            'exercise_count' => 1,
            'exercise_minutes' => 45,
        ]);

        $history = $this->getJson('/api/exercise?date=2026-07-21');
        $history->assertOk()
            ->assertJsonCount(1, 'logs')
            ->assertJsonPath('logs.0.type', 'Yoga')
            ->assertJsonPath('logs.0.durationSeconds', 2700);

        $list = $this->getJson('/api/exercise');
        $list->assertOk()
            ->assertJsonCount(2, 'logs')
            ->assertJsonFragment(['type' => 'Yoga'])
            ->assertJsonFragment(['type' => 'Walk']);

        $logId = $create->json('log.id');
        $delete = $this->deleteJson('/api/exercise/'.$logId);
        $delete->assertOk()
            ->assertJsonCount(0, 'logs');

        $this->assertDatabaseMissing('exercise_logs', [
            'user_id' => $user->id,
            'type' => 'Yoga',
        ]);
    }

    public function test_exercise_gallery_history_is_paged_photo_only_and_private(): void
    {
        $user = User::factory()->create(['name' => 'Gallery User']);
        $otherUser = User::factory()->create(['name' => 'Other User']);

        $startPhotoLog = ExerciseLog::create([
            'id' => 'exercise-gallery-start-photo',
            'user_id' => $user->id,
            'username' => $user->name,
            'type' => 'Yoga',
            'duration_minutes' => 30,
            'duration_seconds' => 1800,
            'intensity' => 2,
            'start_photo_url' => 'https://example.test/yoga-start.jpg',
            'date' => '2026-07-22',
        ]);
        $endPhotoLog = ExerciseLog::create([
            'id' => 'exercise-gallery-end-photo',
            'user_id' => $user->id,
            'username' => $user->name,
            'type' => 'Run',
            'duration_minutes' => 45,
            'duration_seconds' => 2700,
            'intensity' => 3,
            'end_photo_url' => 'https://example.test/run-end.jpg',
            'date' => '2026-07-21',
        ]);
        ExerciseLog::create([
            'id' => 'exercise-gallery-no-photo',
            'user_id' => $user->id,
            'username' => $user->name,
            'type' => 'Walk',
            'duration_minutes' => 20,
            'duration_seconds' => 1200,
            'intensity' => 1,
            'date' => '2026-07-23',
        ]);
        ExerciseLog::create([
            'id' => 'exercise-gallery-other-user',
            'user_id' => $otherUser->id,
            'username' => $otherUser->name,
            'type' => 'Cycling',
            'duration_minutes' => 60,
            'duration_seconds' => 3600,
            'intensity' => 2,
            'start_photo_url' => 'https://example.test/private.jpg',
            'date' => '2026-07-24',
        ]);

        Sanctum::actingAs($user);

        $firstPage = $this->getJson('/api/exercise/history?perPage=1');
        $firstPage->assertOk()
            ->assertJsonCount(1, 'logs')
            ->assertJsonPath('logs.0.id', $startPhotoLog->id)
            ->assertJsonPath('logs.0.startPhotoUrl', 'https://example.test/yoga-start.jpg')
            ->assertJsonPath('page', 1)
            ->assertJsonPath('perPage', 1)
            ->assertJsonPath('hasMore', true);

        $secondPage = $this->getJson('/api/exercise/history?perPage=1&page=2');
        $secondPage->assertOk()
            ->assertJsonCount(1, 'logs')
            ->assertJsonPath('logs.0.id', $endPhotoLog->id)
            ->assertJsonPath('logs.0.endPhotoUrl', 'https://example.test/run-end.jpg')
            ->assertJsonPath('page', 2)
            ->assertJsonPath('hasMore', false);
    }
}
