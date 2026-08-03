<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\Notification;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommunityPostHeartTest extends TestCase
{
    use RefreshDatabase;

    private function makePost(User $owner): CommunityPost
    {
        return CommunityPost::create([
            'user_id' => (string) $owner->id,
            'username' => $owner->name,
            'title' => 'A post',
            'note' => ['text' => 'hello'],
            'category' => 'General',
            'saved' => false,
        ]);
    }

    public function test_hearting_a_post_notifies_the_owner_but_not_when_hearting_your_own(): void
    {
        $owner = User::factory()->create(['name' => 'Post Owner']);
        $fan = User::factory()->create(['name' => 'A Fan']);
        $post = $this->makePost($owner);

        Sanctum::actingAs($fan);

        $response = $this->postJson('/api/community/posts/'.$post->id.'/hearts');

        $response->assertOk()
            ->assertJsonPath('heartsCount', 1)
            ->assertJsonPath('heartedByMe', true);

        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $owner->id,
            'type' => 'community_heart',
        ]);

        // Self-heart: no notification.
        Notification::query()->delete();
        Sanctum::actingAs($owner);
        $selfHeart = $this->postJson('/api/community/posts/'.$post->id.'/hearts');
        $selfHeart->assertOk()->assertJsonPath('heartsCount', 2);

        $this->assertDatabaseMissing('notifications', [
            'user_id' => (string) $owner->id,
            'type' => 'community_heart',
        ]);
    }

    public function test_hearting_the_same_post_twice_from_the_same_user_does_not_duplicate(): void
    {
        $owner = User::factory()->create();
        $fan = User::factory()->create();
        $post = $this->makePost($owner);

        Sanctum::actingAs($fan);

        $first = $this->postJson('/api/community/posts/'.$post->id.'/hearts');
        $first->assertOk()->assertJsonPath('heartsCount', 1);

        $second = $this->postJson('/api/community/posts/'.$post->id.'/hearts');
        $second->assertOk()->assertJsonPath('heartsCount', 1);

        $this->assertSame(
            1,
            \App\Models\CommunityPostHeart::query()
                ->where('community_post_id', $post->id)
                ->where('user_id', $fan->id)
                ->count(),
        );

        // Only the first tap should have notified the owner.
        $this->assertSame(
            1,
            Notification::query()
                ->where('user_id', (string) $owner->id)
                ->where('type', 'community_heart')
                ->count(),
        );
    }

    public function test_unhearting_removes_the_reaction_and_updates_the_count(): void
    {
        $owner = User::factory()->create();
        $fan = User::factory()->create();
        $post = $this->makePost($owner);

        Sanctum::actingAs($fan);
        $this->postJson('/api/community/posts/'.$post->id.'/hearts')->assertOk();

        $response = $this->deleteJson('/api/community/posts/'.$post->id.'/hearts');
        $response->assertOk()
            ->assertJsonPath('heartsCount', 0)
            ->assertJsonPath('heartedByMe', false);

        $this->assertDatabaseMissing('community_post_hearts', [
            'community_post_id' => $post->id,
            'user_id' => $fan->id,
        ]);

        // Unhearting a post you never hearted is a harmless no-op.
        $again = $this->deleteJson('/api/community/posts/'.$post->id.'/hearts');
        $again->assertOk()->assertJsonPath('heartsCount', 0);
    }

    public function test_post_listing_reflects_hearts_count_and_whether_the_viewer_hearted_it(): void
    {
        $owner = User::factory()->create(['name' => 'Owner']);
        $fan = User::factory()->create(['name' => 'Fan']);
        $bystander = User::factory()->create(['name' => 'Bystander']);
        $post = $this->makePost($owner);

        Sanctum::actingAs($fan);
        $this->postJson('/api/community/posts/'.$post->id.'/hearts')->assertOk();

        $fanView = $this->getJson('/api/community/posts?category=General');
        $fanView->assertOk();
        $fanPost = collect($fanView->json('posts'))->firstWhere('id', (string) $post->id);
        $this->assertSame(1, $fanPost['heartsCount']);
        $this->assertTrue($fanPost['heartedByMe']);

        Sanctum::actingAs($bystander);
        $bystanderView = $this->getJson('/api/community/posts?category=General');
        $bystanderView->assertOk();
        $bystanderPost = collect($bystanderView->json('posts'))->firstWhere('id', (string) $post->id);
        $this->assertSame(1, $bystanderPost['heartsCount']);
        $this->assertFalse($bystanderPost['heartedByMe']);
    }
}
