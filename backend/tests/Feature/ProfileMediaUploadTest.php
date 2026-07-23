<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ProfileMediaUploadTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_user_can_upload_profile_media_to_the_public_disk(): void
    {
        Storage::fake('public');
        config()->set('filesystems.media_upload_disk', 'public');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->post('/api/media/upload', [
            'kind' => 'avatar',
            'file' => UploadedFile::fake()->image('avatar.jpg'),
        ]);

        $response->assertOk()
            ->assertJsonStructure([
                'url',
                'profile_pic',
                'path',
                'user',
            ]);

        $path = $response->json('path');
        $url = $response->json('url');

        $this->assertIsString($path);
        $this->assertIsString($url);

        Storage::disk('public')->assertExists($path);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => $url,
        ]);
    }
}
