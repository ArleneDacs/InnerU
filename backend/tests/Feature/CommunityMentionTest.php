<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommunityMentionTest extends TestCase
{
    use RefreshDatabase;

    public function test_search_returns_matching_users_in_the_same_company_only(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        $sameCompany = User::factory()->create(['company_code' => 'ACME', 'name' => 'Jordan Rivera']);
        $otherCompany = User::factory()->create(['company_code' => 'OTHER', 'name' => 'Jordan Smith']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=Jordan');

        $response->assertOk();
        $names = collect($response->json())->pluck('name')->all();
        $this->assertContains('Jordan Rivera', $names);
        $this->assertNotContains('Jordan Smith', $names);
    }

    public function test_search_is_capped_at_10_results(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        User::factory()->count(15)->create(['company_code' => 'ACME', 'name' => 'Test Match User']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=Test');

        $response->assertOk();
        $this->assertLessThanOrEqual(10, count($response->json()));
    }

    public function test_a_blank_query_returns_an_empty_list_not_the_whole_company(): void
    {
        $me = User::factory()->create(['company_code' => 'ACME']);
        User::factory()->count(3)->create(['company_code' => 'ACME']);

        Sanctum::actingAs($me);
        $response = $this->getJson('/api/community/mentionable-users?q=');

        $response->assertOk();
        $this->assertCount(0, $response->json());
    }

    public function test_mentioning_a_user_in_a_post_stores_the_mention_and_notifies_them(): void
    {
        $author = User::factory()->create(['company_code' => 'ACME']);
        $mentioned = User::factory()->create(['company_code' => 'ACME', 'name' => 'Jordan Rivera']);

        Sanctum::actingAs($author);
        $response = $this->postJson('/api/community/posts', [
            'title' => 'Test post',
            'category' => 'General',
            'note' => [['type' => 'text', 'value' => 'hey @Jordan Rivera check this out']],
            'color' => 0xFFFFFFFF,
            'mentions' => [['userId' => (string) $mentioned->id, 'name' => 'Jordan Rivera']],
        ]);

        $response->assertCreated()->assertJsonPath('post.mentions.0.userId', (string) $mentioned->id);
        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $mentioned->id,
            'type' => 'community_mention',
        ]);

        $this->getJson('/api/community/posts?category=General')
            ->assertOk()
            ->assertJsonPath('posts.0.mentions.0.userId', (string) $mentioned->id);
    }

    public function test_post_titles_cannot_exceed_fifty_characters(): void
    {
        $author = User::factory()->create(['company_code' => 'ACME']);

        Sanctum::actingAs($author);
        $response = $this->postJson('/api/community/posts', [
            'title' => str_repeat('x', 51),
            'category' => 'General',
            'note' => [['type' => 'text', 'value' => 'A post body']],
            'color' => 0xFFFFFFFF,
        ]);

        $response->assertUnprocessable()->assertJsonValidationErrors('title');
    }

    public function test_mentioning_a_user_outside_the_company_is_rejected(): void
    {
        $author = User::factory()->create(['company_code' => 'ACME']);
        $outsider = User::factory()->create(['company_code' => 'OTHER']);

        Sanctum::actingAs($author);
        $response = $this->postJson('/api/community/posts', [
            'title' => 'Test post',
            'category' => 'General',
            'note' => [['type' => 'text', 'value' => 'hey there']],
            'color' => 0xFFFFFFFF,
            'mentions' => [['userId' => (string) $outsider->id, 'name' => 'Outsider']],
        ]);

        $response->assertStatus(422);
    }

    public function test_mentioning_yourself_does_not_notify_you(): void
    {
        $author = User::factory()->create(['company_code' => 'ACME']);

        Sanctum::actingAs($author);
        $this->postJson('/api/community/posts', [
            'title' => 'Test post',
            'category' => 'General',
            'note' => [['type' => 'text', 'value' => 'talking to myself']],
            'color' => 0xFFFFFFFF,
            'mentions' => [['userId' => (string) $author->id, 'name' => $author->name]],
        ])->assertCreated();

        $this->assertDatabaseMissing('notifications', [
            'user_id' => (string) $author->id,
            'type' => 'community_mention',
        ]);
    }

    public function test_mentioning_a_user_in_a_comment_stores_the_mention_and_notifies_them(): void
    {
        $postOwner = User::factory()->create(['company_code' => 'ACME']);
        $commenter = User::factory()->create(['company_code' => 'ACME']);
        $mentioned = User::factory()->create(['company_code' => 'ACME', 'name' => 'Jordan Rivera']);
        $post = CommunityPost::create([
            'user_id' => $postOwner->id, 'username' => $postOwner->name, 'title' => 'Test',
            'note' => [['type' => 'text', 'value' => 'x']], 'color' => 0xFFFFFFFF,
            'category' => 'General', 'saved' => false,
        ]);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'hey @Jordan Rivera look',
            'mentions' => [['userId' => (string) $mentioned->id, 'name' => 'Jordan Rivera']],
        ]);

        $response->assertCreated()->assertJsonPath('comment.mentions.0.userId', (string) $mentioned->id);
        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $mentioned->id,
            'type' => 'community_mention',
        ]);
    }
}
