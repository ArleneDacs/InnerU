<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ProfileMediaUploadTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_user_can_upload_profile_media_to_the_cloud_disk(): void
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

        Storage::disk('do')->assertExists($path);

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
        Storage::disk('do')->assertExists($path);

        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => null,
        ]);
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
        Storage::disk('s3')->assertExists($path);
        Storage::disk('public')->assertMissing($path);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => null,
        ]);
    }

    public function test_authenticated_user_can_upload_profile_media_even_when_profile_pic_column_is_unavailable(): void
    {
        Storage::fake('do');
        config()->set('filesystems.media_upload_disk', 'do');
        config()->set('filesystems.media_upload_path', 'uploads');
        Schema::shouldReceive('hasColumn')
            ->once()
            ->with('users', 'profile_pic')
            ->andReturn(false);

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
        $this->assertSame($url, $response->json('profile_pic'));
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'profile_pic' => null,
        ]);

        Storage::disk('do')->assertExists($path);
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
