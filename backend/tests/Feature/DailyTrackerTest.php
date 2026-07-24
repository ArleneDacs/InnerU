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

    public function test_non_admin_cannot_view_admin_daily_tracker_overview(): void
    {
        $user = User::factory()->create(['role' => 'user']);
        Sanctum::actingAs($user);

        $response = $this->getJson('/api/admin/daily-tracker');

        $response->assertStatus(401);
    }

    public function test_admin_can_view_daily_tracker_overview_for_all_users(): void
    {
        $admin = User::factory()->create(['role' => 'admin', 'is_admin' => true]);
        $memberA = User::factory()->create([
            'name' => 'Member A',
            'email' => 'member-a@example.com',
            'company_name' => 'ABC',
        ]);
        $memberB = User::factory()->create([
            'name' => 'Member B',
            'email' => 'member-b@example.com',
            'company_name' => 'ABC',
        ]);

        $today = now()->toDateString();

        DailyTracker::create([
            'user_id' => (string) $memberA->id,
            'username' => $memberA->name,
            'date' => $today,
            'call' => true,
            'steps' => true,
            'exercise' => true,
            'meditation' => false,
            'learning' => false,
            'add_value' => false,
        ]);

        Sanctum::actingAs($admin);

        $response = $this->getJson(
            '/api/admin/daily-tracker?month='.now()->format('Y-m')
        );

        $response->assertOk()
            ->assertJsonPath('date', $today);

        $users = collect($response->json('users'));
        $this->assertCount(3, $users);

        $memberAPayload = $users->firstWhere('userId', (string) $memberA->id);
        $this->assertNotNull($memberAPayload);
        $this->assertSame(3, $memberAPayload['todayCompletedCount']);
        $this->assertSame(6, $memberAPayload['todayTaskCount']);
        $this->assertTrue($memberAPayload['progress'][$today]['Call']);
        $this->assertFalse($memberAPayload['progress'][$today]['Meditation']);

        $memberBPayload = $users->firstWhere('userId', (string) $memberB->id);
        $this->assertNotNull($memberBPayload);
        $this->assertSame(0, $memberBPayload['todayCompletedCount']);
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }
}
