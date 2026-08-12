<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class DefaultLandingScreenTest extends TestCase
{
    use RefreshDatabase;

    public function test_default_landing_screen_persists_to_profile_and_a_fresh_login_payload(): void
    {
        $user = User::factory()->create([
            'default_landing_screen' => 'dashboard',
            'email_verified_at' => now(),
            'password' => Hash::make('Password123'),
        ]);
        Sanctum::actingAs($user);

        $this->patchJson('/api/me', [
            'default_landing_screen' => 'profile',
        ])->assertOk()
            ->assertJsonPath('user.defaultScreen', 'profile');

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'default_landing_screen' => 'profile',
        ]);

        $this->getJson('/api/me')->assertOk()
            ->assertJsonPath('user.defaultScreen', 'profile');

        $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'Password123',
        ])->assertOk()
            ->assertJsonPath('user.defaultScreen', 'profile')
            ->assertJsonStructure([
                'token_type',
                'token',
                'user' => ['defaultScreen'],
            ]);
    }

    public function test_default_landing_screen_rejects_values_outside_the_supported_destinations(): void
    {
        $user = User::factory()->create([
            'default_landing_screen' => 'dashboard',
        ]);
        Sanctum::actingAs($user);

        $this->patchJson('/api/me', [
            'default_landing_screen' => 'not-a-screen',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('default_landing_screen');

        $this->assertSame('dashboard', $user->fresh()->default_landing_screen);
    }
}
