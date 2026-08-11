<?php

namespace Tests\Feature;

use App\Models\DailyTracker;
use App\Models\Notification;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class StepGoalAchievementTest extends TestCase
{
    use RefreshDatabase;

    public function test_step_medals_use_actual_goal_completion_and_are_idempotent(): void
    {
        $user = User::factory()->create(['name' => 'Step Medal User']);
        Sanctum::actingAs($user);

        // The old `steps` checklist flag is intentionally not sufficient.
        $belowGoal = $this->saveSteps('2026-08-01', 4_999, 5_000, true);
        $belowGoal->assertOk()
            ->assertJsonPath('stepGoalAchievement.goalMet', false)
            ->assertJsonCount(0, 'stepGoalAchievement.newRewards');

        $this->saveSteps('2026-08-01', 5_000, 5_000, true)
            ->assertJsonCount(0, 'stepGoalAchievement.newRewards');
        $this->saveSteps('2026-08-02', 5_000, 5_000, true)
            ->assertJsonCount(0, 'stepGoalAchievement.newRewards');

        $unlocked = $this->saveSteps('2026-08-03', 5_000, 5_000, true);
        $unlocked->assertOk()
            ->assertJsonPath('stepGoalAchievement.goalMet', true)
            ->assertJsonPath('stepGoalAchievement.currentStreak', 3)
            ->assertJsonPath('stepGoalAchievement.longestStreak', 3)
            ->assertJsonPath('stepGoalAchievement.newRewards.0.id', 'first_stride')
            ->assertJsonPath('stepGoalAchievement.newRewards.0.unlockedAt', '2026-08-03');

        $freshUser = $user->fresh();
        $this->assertSame(3, $freshUser->steps_streak_current);
        $this->assertSame(3, $freshUser->steps_streak_longest);
        $this->assertSame('2026-08-03', $freshUser->steps_streak_last_date);
        $this->assertSame('2026-08-03', $freshUser->steps_streak_rewards['first_stride']);
        $this->assertSame(1, Notification::query()
            ->where('user_id', (string) $user->id)
            ->where('type', 'streak_milestone')
            ->count());

        // Repeated device/background writes for the same completed date must
        // return no new reward and create no duplicate notification.
        $retry = $this->saveSteps('2026-08-03', 5_250, 5_000, true);
        $retry->assertOk()
            ->assertJsonCount(0, 'stepGoalAchievement.newRewards');
        $this->assertSame(1, Notification::query()
            ->where('user_id', (string) $user->id)
            ->where('type', 'streak_milestone')
            ->count());
    }

    public function test_out_of_order_offline_dates_can_join_a_streak_and_unlock_once(): void
    {
        $user = User::factory()->create(['name' => 'Offline Step User']);
        Sanctum::actingAs($user);

        $this->saveSteps('2026-08-03', 8_200, 8_200)
            ->assertJsonCount(0, 'stepGoalAchievement.newRewards');
        $this->saveSteps('2026-08-01', 8_200, 8_200)
            ->assertJsonCount(0, 'stepGoalAchievement.newRewards');

        // The late middle day joins both recorded runs. The achievement
        // service queries the bounded affected window around this date.
        $joined = $this->saveSteps('2026-08-02', 8_200, 8_200);
        $joined->assertOk()
            ->assertJsonPath('stepGoalAchievement.currentStreak', 3)
            ->assertJsonPath('stepGoalAchievement.longestStreak', 3)
            ->assertJsonPath('stepGoalAchievement.newRewards.0.id', 'first_stride');

        $this->assertSame(1, Notification::query()
            ->where('user_id', (string) $user->id)
            ->where('type', 'streak_milestone')
            ->count());
    }

    public function test_one_hundred_day_milestone_is_evaluated_from_bounded_history(): void
    {
        $user = User::factory()->create(['name' => 'Long Step User']);
        Sanctum::actingAs($user);

        // Seed the first 99 daily completions as prior synced history, then
        // submit day 100 through the public endpoint. The service only needs
        // the 100-day milestone window around the changed tracker.
        $start = now()->setDate(2026, 1, 1)->startOfDay();
        for ($offset = 0; $offset < 99; $offset++) {
            DailyTracker::create([
                'user_id' => (string) $user->id,
                'username' => $user->name,
                'date' => $start->copy()->addDays($offset)->toDateString(),
                'step_count' => 5_000,
                'step_goal' => 5_000,
            ]);
        }

        $day100 = $start->copy()->addDays(99)->toDateString();
        $response = $this->saveSteps($day100, 5_000, 5_000);
        $response->assertOk()
            ->assertJsonPath('stepGoalAchievement.currentStreak', 100)
            ->assertJsonPath('stepGoalAchievement.longestStreak', 100)
            ->assertJsonCount(6, 'stepGoalAchievement.newRewards')
            ->assertJsonPath('stepGoalAchievement.newRewards.5.id', 'unbroken_path');
    }

    public function test_legacy_step_state_is_not_reset_without_server_goal_completions(): void
    {
        $user = User::factory()->create([
            'steps_streak_current' => 7,
            'steps_streak_longest' => 14,
            'steps_streak_last_date' => '2026-07-31',
            'steps_streak_rewards' => ['first_stride' => '2026-07-27'],
        ]);
        Sanctum::actingAs($user);

        $response = $this->saveSteps('2026-08-01', 4_000, 5_000, true);
        $response->assertOk()
            ->assertJsonPath('stepGoalAchievement.goalMet', false)
            ->assertJsonPath('stepGoalAchievement.currentStreak', 7)
            ->assertJsonPath('stepGoalAchievement.longestStreak', 14)
            ->assertJsonPath('stepGoalAchievement.lastCompletedDate', '2026-07-31')
            ->assertJsonCount(0, 'stepGoalAchievement.newRewards');

        $freshUser = $user->fresh();
        $this->assertSame(7, $freshUser->steps_streak_current);
        $this->assertSame(14, $freshUser->steps_streak_longest);
        $this->assertSame('2026-07-31', $freshUser->steps_streak_last_date);
    }

    public function test_clients_cannot_write_step_streak_state_or_create_steps_notifications(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $profile = $this->patchJson('/api/me', [
            'steps_streak_current' => 99,
            'steps_streak_rewards' => ['unbroken_path' => '2026-08-01'],
        ]);
        $profile->assertOk()
            ->assertJsonPath('user.stepsStreakCurrent', null)
            ->assertJsonPath('user.stepsStreakRewards', []);

        $legacyNotification = $this->postJson('/api/notifications/streak', [
            'milestone' => 'First Stride',
            'days' => 3,
            'activity' => 'Steps',
        ]);
        $legacyNotification->assertUnprocessable();
        $this->assertSame(0, Notification::query()->count());
    }

    private function saveSteps(
        string $date,
        int $stepCount,
        int $stepGoal,
        bool $steps = true,
    ) {
        return $this->postJson('/api/daily-tracker', [
            'date' => $date,
            'step_count' => $stepCount,
            'step_goal' => $stepGoal,
            'steps' => $steps,
        ]);
    }
}
