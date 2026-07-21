<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CalorieTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_can_manage_calorie_days_entries_and_food_memory(): void
    {
        $user = User::factory()->create([
            'name' => 'Calorie User',
            'email' => 'calorie@example.com',
            'company_code' => 'ABC',
            'company_name' => 'ABC',
        ]);

        Sanctum::actingAs($user);

        $goal = $this->postJson('/api/calorie/day', [
            'date' => '2026-07-21',
            'daily_goal' => 2200,
            'water_glasses' => 3,
            'water_goal' => 8,
        ]);

        $goal->assertOk()
            ->assertJsonPath('day.dailyGoal', 2200)
            ->assertJsonPath('day.waterGlasses', 3);

        $entry = $this->postJson('/api/calorie/entries', [
            'date' => '2026-07-21',
            'meal' => 'Chicken Rice',
            'meal_type' => 'Lunch',
            'calories' => 650,
            'protein' => 40,
            'carbs' => 70,
            'fat' => 12,
            'quantity' => 1,
            'measurement_unit' => 'plate',
            'photo_url' => 'https://example.com/photo.jpg',
        ]);

        $entry->assertCreated()
            ->assertJsonPath('day.totalCalories', 650)
            ->assertJsonPath('entries.0.meal', 'Chicken Rice');

        $this->assertDatabaseHas('calorie_days', [
            'user_id' => $user->id,
            'date' => '2026-07-21',
            'daily_goal' => 2200,
            'total_calories' => 650,
            'water_glasses' => 3,
        ]);

        $history = $this->getJson('/api/calorie/history?limit=10');
        $history->assertOk()
            ->assertJsonCount(1, 'days')
            ->assertJsonPath('days.0.totalCalories', 650);

        $show = $this->getJson('/api/calorie?date=2026-07-21');
        $show->assertOk()
            ->assertJsonPath('day.dailyGoal', 2200)
            ->assertJsonCount(1, 'entries');

        $memory = $this->postJson('/api/calorie/food-memory', [
            'key' => 'chicken_rice',
            'display_name' => 'Chicken Rice',
            'lookup_name' => 'chicken rice',
            'calories' => 650,
            'protein' => 40,
            'carbs' => 70,
            'fat' => 12,
            'source' => 'online_lookup',
        ]);

        $memory->assertOk()
            ->assertJsonPath('memory.key', 'chicken_rice');

        $lookup = $this->getJson('/api/calorie/food-memory/chicken_rice');
        $lookup->assertOk()
            ->assertJsonPath('memory.displayName', 'Chicken Rice');
    }
}
