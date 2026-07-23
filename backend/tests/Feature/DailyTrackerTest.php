<?php

namespace Tests\Feature;

use App\Models\DailyTracker;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Mockery;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DailyTrackerTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_save_and_load_daily_tracker(): void
    {
        $user = User::factory()->create([
            'name' => 'Step User',
            'email' => 'step@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
            'daily_step_goal' => 8200,
        ]);

        Sanctum::actingAs($user);

        $save = $this->postJson('/api/daily-tracker', [
            'date' => '2026-07-21',
            'step_count' => 1432,
            'step_goal' => 8200,
            'steps' => true,
            'meditation' => false,
            'username' => 'Step User',
            'company_id' => 'ABC',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);

        $save->assertOk()
            ->assertJsonPath('tracker.stepCount', 1432)
            ->assertJsonPath('tracker.stepGoal', 8200)
            ->assertJsonPath('tracker.steps', true);

        $this->assertDatabaseHas('daily_trackers', [
            'user_id' => $user->id,
            'date' => '2026-07-21',
            'step_count' => 1432,
            'step_goal' => 8200,
            'steps' => true,
        ]);

        $load = $this->getJson('/api/daily-tracker?date=2026-07-21');

        $load->assertOk()
            ->assertJsonPath('tracker.stepCount', 1432)
            ->assertJsonPath('tracker.stepGoal', 8200)
            ->assertJsonPath('tracker.username', 'Step User');
    }

    public function test_user_can_save_daily_tracker_even_if_score_sync_fails(): void
    {
        $user = User::factory()->create([
            'name' => 'Step User',
            'email' => 'step-sync-fail@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
            'daily_step_goal' => 8200,
        ]);

        $scoreService = Mockery::mock(UserScoreService::class);
        $scoreService->shouldReceive('resolveForUser')
            ->once()
            ->andThrow(new \RuntimeException('Score sync failed.'));
        app()->instance(UserScoreService::class, $scoreService);

        Sanctum::actingAs($user);

        $save = $this->postJson('/api/daily-tracker', [
            'date' => '2026-07-21',
            'step_count' => 1432,
            'step_goal' => 8200,
            'steps' => true,
            'meditation' => false,
            'username' => 'Step User',
            'company_id' => 'ABC',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);

        $save->assertOk()
            ->assertJsonPath('tracker.stepCount', 1432)
            ->assertJsonPath('tracker.stepGoal', 8200)
            ->assertJsonPath('tracker.steps', true);

        $this->assertDatabaseHas('daily_trackers', [
            'user_id' => $user->id,
            'date' => '2026-07-21',
            'step_count' => 1432,
            'step_goal' => 8200,
            'steps' => true,
        ]);
    }

    public function test_score_reflects_todays_completion_not_diluted_by_history(): void
    {
        $user = User::factory()->create();

        for ($i = 1; $i <= 20; $i++) {
            DailyTracker::create([
                'user_id' => (string) $user->id,
                'username' => $user->name,
                'date' => now()->subDays($i)->toDateString(),
                'call' => false,
                'steps' => false,
                'exercise' => false,
                'meditation' => false,
                'learning' => false,
                'add_value' => false,
            ]);
        }

        DailyTracker::create([
            'user_id' => (string) $user->id,
            'username' => $user->name,
            'date' => now()->toDateString(),
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => true,
            'learning' => true,
            'add_value' => true,
        ]);

        $breakdown = app(UserScoreService::class)->resolveBreakdownForUser($user->fresh());

        $this->assertEquals(100.0, $breakdown['coreTaskScore']);
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }
}
