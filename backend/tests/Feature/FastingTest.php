<?php

namespace Tests\Feature;

use App\Models\FastingHistory;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class FastingTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_start_end_and_view_fasting_history(): void
    {
        $user = User::factory()->create([
            'name' => 'Fasting User',
            'email' => 'fasting@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);

        Sanctum::actingAs($user);

        $start = $this->postJson('/api/fasting/start', [
            'target_hours' => 16,
        ]);

        $start->assertOk()
            ->assertJsonPath('session.targetHours', 16);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'fasting_target_hours' => 16,
        ]);

        $end = $this->postJson('/api/fasting/end');
        $end->assertOk()
            ->assertJsonPath('session.startTime', null);

        $this->assertDatabaseHas('fasting_history', [
            'user_id' => $user->id,
            'target_hours' => 16,
        ]);

        $history = $this->getJson('/api/fasting/history?limit=10');
        $history->assertOk()
            ->assertJsonCount(1, 'history')
            ->assertJsonPath('history.0.targetHours', 16);

        $show = $this->getJson('/api/fasting');
        $show->assertOk()
            ->assertJsonPath('session.targetHours', 16);
    }
}
