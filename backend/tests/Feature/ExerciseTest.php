<?php

namespace Tests\Feature;

use App\Models\DailyTracker;
use App\Models\ExerciseLog;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ExerciseTest extends TestCase
{
    use RefreshDatabase;

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
}
