<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\CommunityPostHeart;
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
        $notification = Notification::query()
            ->where('user_id', (string) $owner->id)
            ->where('type', 'community_heart')
            ->firstOrFail();
        $this->assertSame((string) $post->id, $notification->data['postId'] ?? null);

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

    public function test_liker_identities_are_paged_and_bounded_for_a_visible_post(): void
    {
        $owner = User::factory()->create(['name' => 'Post Owner']);
        $post = $this->makePost($owner);
        $fans = User::factory()->count(3)->sequence(
            ['name' => 'First Fan'],
            ['name' => 'Second Fan'],
            ['name' => 'Third Fan'],
        )->create();

        foreach ($fans as $fan) {
            CommunityPostHeart::create([
                'community_post_id' => $post->id,
                'user_id' => $fan->id,
            ]);
        }

        Sanctum::actingAs($owner);
        $firstPage = $this->getJson('/api/community/posts/'.$post->id.'/hearts?perPage=2');

        $firstPage->assertOk()
            ->assertJsonPath('heartsCount', 3)
            ->assertJsonPath('page', 1)
            ->assertJsonPath('perPage', 2)
            ->assertJsonPath('hasMore', true)
            ->assertJsonCount(2, 'likers');
        $this->assertContains(
            $firstPage->json('likers.0.name'),
            ['First Fan', 'Second Fan', 'Third Fan'],
        );

        $secondPage = $this->getJson('/api/community/posts/'.$post->id.'/hearts?perPage=2&page=2');
        $secondPage->assertOk()
            ->assertJsonPath('hasMore', false)
            ->assertJsonCount(1, 'likers');

        // The API enforces its maximum even if a client asks for an
        // unreasonably large page, keeping a hover/popover response small.
        $bounded = $this->getJson('/api/community/posts/'.$post->id.'/hearts?perPage=999');
        $bounded->assertOk()->assertJsonPath('perPage', 25);
    }

    public function test_liker_identities_do_not_expose_a_private_saved_post(): void
    {
        $owner = User::factory()->create(['company_code' => 'ACME']);
        $otherMember = User::factory()->create(['company_code' => 'ACME']);
        $post = $this->makePost($owner);
        $post->update(['saved' => true]);

        Sanctum::actingAs($otherMember);
        $this->getJson('/api/community/posts/'.$post->id.'/hearts')->assertNotFound();
    }

    public function test_targeted_post_endpoint_returns_the_exact_notification_destination(): void
    {
        $owner = User::factory()->create(['name' => 'Post Owner']);
        $post = $this->makePost($owner);

        Sanctum::actingAs($owner);
        $this->getJson('/api/community/posts/'.$post->id)
            ->assertOk()
            ->assertJsonPath('post.id', (string) $post->id)
            ->assertJsonPath('post.title', 'A post');
    }
}
