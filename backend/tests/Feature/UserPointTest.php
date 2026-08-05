<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Mockery;
use Tests\TestCase;

class UserPointTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_save_user_points_even_if_score_sync_fails(): void
    {
        $user = User::factory()->create([
            'name' => 'Point User',
            'email' => 'point-user@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);

        $scoreService = Mockery::mock(UserScoreService::class);
        $scoreService->shouldReceive('syncForUser')
            ->once()
            ->andThrow(new \RuntimeException('Score sync failed.'));
        app()->instance(UserScoreService::class, $scoreService);

        Sanctum::actingAs($user);

        $response = $this->postJson('/api/user-points', [
            'date' => '2026-07-21',
            'username' => 'Point User',
            'total_points' => 65,
            'activity_points' => 30,
            'daily_tracker_score' => 50,
            'todo_list_score' => 10,
            'todo_list_score_daily_contribution' => 5,
            'todo_list_included_in_total' => true,
            'user_total_score' => 65,
            'task_points' => [
                'Steps' => 10,
            ],
            'tasks' => [
                'Steps' => true,
            ],
            'server' => 'Default',
            'company_id' => 'ABC',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
            'activity_counts' => [
                'stepCount' => 1432,
            ],
        ]);

        $response->assertOk()
            ->assertJsonPath('point.username', 'Point User')
            ->assertJsonPath('point.totalPoints', 65)
            ->assertJsonPath('point.dailyTrackerScore', 50);

        $this->assertDatabaseHas('user_points', [
            'user_id' => $user->id,
            'date' => '2026-07-21',
            'username' => 'Point User',
            'company_id' => 'ABC',
        ]);
    }

    public function test_fractional_scores_are_rounded_before_being_stored(): void
    {
        // The leaderboard ranking score comes only from daily tracker
        // activity, so daily_tracker_score=50 resolves to overallScore=50
        // regardless of todo_list_score -- goalScore (25) is still computed
        // and returned separately for informational display, but it no
        // longer factors into the ranking. user_points.user_total_score is
        // an INTEGER column; writing a raw float here previously crashed
        // against Postgres (SQLite silently tolerated it) because the
        // controller wrote resolveForUser()'s raw float directly instead of
        // the already-rounded value syncForUser() produces for users.score
        // -- this still exercises that write path end to end.
        $user = User::factory()->create([
            'name' => 'Fractional Point User',
            'email' => 'fractional-point@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);

        Sanctum::actingAs($user);

        $response = $this->postJson('/api/user-points', [
            'date' => '2026-07-21',
            'username' => 'Fractional Point User',
            'total_points' => 75,
            'activity_points' => 30,
            'daily_tracker_score' => 50,
            'todo_list_score' => 25,
            'todo_list_score_daily_contribution' => 25,
            'todo_list_included_in_total' => true,
            'user_total_score' => 75,
            'task_points' => [],
            'tasks' => [],
            'server' => 'Default',
            'company_id' => 'ABC',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
            'activity_counts' => [],
        ]);

        $response->assertOk();

        $storedScore = DB::table('user_points')
            ->where('user_id', $user->id)
            ->where('date', '2026-07-21')
            ->value('user_total_score');

        $this->assertEquals(50, $storedScore);
    }

    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }
}
