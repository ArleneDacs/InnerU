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

    public function test_avatar_upload_is_storage_only_until_profile_pic_is_explicitly_updated(): void
    {
        Storage::fake('do');
        config()->set('filesystems.media_upload_disk', 'do');
        config()->set('filesystems.media_upload_path', 'uploads');

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
        $this->assertStringStartsWith('uploads/', $path);
        $this->assertSame($url, $response->json('profile_pic'));

        Storage::disk('do')->assertExists($path);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => null,
        ]);
        $response->assertJsonPath('user.profile_pic', null);

        $updateResponse = $this->patchJson('/api/me', [
            'profile_pic' => $url,
        ]);

        $updateResponse->assertOk()
            ->assertJsonPath('user.profile_pic', $url);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => $url,
        ]);
    }

    public function test_authenticated_user_can_upload_community_media_without_updating_profile_pic(): void
    {
        Storage::fake('do');
        config()->set('filesystems.media_upload_disk', 'do');
        config()->set('filesystems.media_upload_path', 'uploads');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->post('/api/media/upload', [
            'kind' => 'community',
            'file' => UploadedFile::fake()->image('community.jpg'),
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
        $this->assertStringStartsWith('uploads/', $path);
        Storage::disk('do')->assertExists($path);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => null,
        ]);
    }

    public function test_exercise_media_retries_reuse_a_deterministic_session_slot_path(): void
    {
        Storage::fake('do');
        config()->set('filesystems.media_upload_disk', 'do');
        config()->set('filesystems.media_upload_path', 'uploads');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $startName = 'exercise_local-session-123_start.jpg';
        $firstStart = $this->post('/api/media/upload', [
            'kind' => 'exercise',
            'file' => UploadedFile::fake()->image($startName),
        ]);

        $expectedStartPath = "uploads/users/{$user->id}/exercise-sessions/local-session-123/start.jpg";
        $firstStart->assertOk()
            ->assertJsonPath('path', $expectedStartPath)
            ->assertJsonPath('uploadKey', 'exercise_local-session-123_start')
            ->assertJsonPath('clientSessionId', 'local-session-123')
            ->assertJsonPath('slot', 'start');

        $replayedStart = $this->post('/api/media/upload', [
            'kind' => 'exercise',
            'file' => UploadedFile::fake()->image($startName),
        ]);

        $replayedStart->assertOk()
            ->assertJsonPath('path', $expectedStartPath)
            ->assertJsonPath('url', $firstStart->json('url'));
        Storage::disk('do')->assertExists($expectedStartPath);
        $this->assertCount(
            1,
            Storage::disk('do')->allFiles("uploads/users/{$user->id}/exercise-sessions/local-session-123"),
        );

        $end = $this->post('/api/media/upload', [
            'kind' => 'exercise',
            'file' => UploadedFile::fake()->image('exercise_local-session-123_end.jpg'),
        ]);

        $expectedEndPath = "uploads/users/{$user->id}/exercise-sessions/local-session-123/end.jpg";
        $end->assertOk()
            ->assertJsonPath('path', $expectedEndPath)
            ->assertJsonPath('slot', 'end');
        Storage::disk('do')->assertExists($expectedEndPath);
        $this->assertCount(
            2,
            Storage::disk('do')->allFiles("uploads/users/{$user->id}/exercise-sessions/local-session-123"),
        );
    }

    public function test_exercise_media_accepts_an_explicit_upload_key_and_rejects_an_ambiguous_filename(): void
    {
        Storage::fake('do');
        config()->set('filesystems.media_upload_disk', 'do');
        config()->set('filesystems.media_upload_path', 'uploads');

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $explicitKey = $this->post('/api/media/upload', [
            'kind' => 'exercise',
            'upload_key' => 'exercise_explicit-key_end',
            'file' => UploadedFile::fake()->image('camera-roll.jpg'),
        ]);

        $explicitKey->assertOk()
            ->assertJsonPath(
                'path',
                "uploads/users/{$user->id}/exercise-sessions/explicit-key/end.jpg",
            )
            ->assertJsonPath('uploadKey', 'exercise_explicit-key_end');

        $invalid = $this->post('/api/media/upload', [
            'kind' => 'exercise',
            'file' => UploadedFile::fake()->image('exercise.jpg'),
        ], [
            'Accept' => 'application/json',
        ]);

        $invalid->assertUnprocessable()
            ->assertJsonValidationErrors(['file']);
    }

    public function test_legacy_exercise_avatar_upload_does_not_update_profile_pic(): void
    {
        Storage::fake('do');
        config()->set('filesystems.media_upload_disk', 'do');
        config()->set('filesystems.media_upload_path', 'uploads');

        $originalProfilePic = 'https://example.com/original-avatar.jpg';
        $user = User::factory()->create([
            'profile_pic' => $originalProfilePic,
        ]);
        Sanctum::actingAs($user);

        $response = $this->post('/api/media/upload', [
            'kind' => 'avatar',
            'file' => UploadedFile::fake()->image('exercise.jpg'),
        ]);

        $response->assertOk();

        $path = $response->json('path');
        $this->assertIsString($path);
        $this->assertStringContainsString(
            "users/{$user->id}/avatars/",
            $path,
        );
        Storage::disk('do')->assertExists($path);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => $originalProfilePic,
        ]);
        $response->assertJsonPath('user.profile_pic', $originalProfilePic);
    }

    public function test_community_media_prefers_s3_when_cloud_storage_is_available(): void
    {
        Storage::fake('s3');
        Storage::fake('public');
        config()->set('filesystems.media_upload_disk', 'public');
        config()->set('filesystems.media_upload_path', 'uploads');
        config()->set('filesystems.disks.s3.bucket', 'inneru-test-bucket');
        config()->set('filesystems.disks.s3.url', 'https://inneru-test-bucket.s3.amazonaws.com');
        config()->set('filesystems.disks.s3.endpoint', null);

        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->post('/api/media/upload', [
            'kind' => 'community',
            'file' => UploadedFile::fake()->image('community.jpg'),
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
        $this->assertStringStartsWith('uploads/', $path);
        Storage::disk('s3')->assertExists($path);
        Storage::disk('public')->assertMissing($path);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => null,
        ]);
    }

    public function test_authenticated_user_can_explicitly_update_profile_pic(): void
    {
        $user = User::factory()->create([
            'profile_pic' => 'https://example.com/original-avatar.jpg',
        ]);
        Sanctum::actingAs($user);

        $newProfilePic = 'https://example.com/new-avatar.jpg';
        $response = $this->patchJson('/api/me', [
            'profile_pic' => $newProfilePic,
        ]);

        $response->assertOk()
            ->assertJsonPath('user.profile_pic', $newProfilePic);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => $newProfilePic,
        ]);
    }

    public function test_authenticated_user_can_upload_profile_media_when_the_configured_disk_is_invalid(): void
    {
        Storage::fake('public');
        config()->set('filesystems.media_upload_disk', 'missing-disk');
        config()->set('filesystems.media_upload_path', 'uploads');

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
        $this->assertStringStartsWith('uploads/', $path);
        Storage::disk('public')->assertExists($path);
    }
}
