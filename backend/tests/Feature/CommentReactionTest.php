<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommentReactionTest extends TestCase
{
    use RefreshDatabase;

    private function makeComment(User $postOwner, User $commenter): array
    {
        $post = CommunityPost::create([
            'user_id' => $postOwner->id,
            'username' => $postOwner->name,
            'title' => 'Test post',
            'note' => [['type' => 'text', 'value' => 'hello']],
            'color' => 0xFFFFFFFF,
            'category' => 'General',
            'saved' => false,
        ]);
        $comment = NoteComment::create([
            'community_post_id' => $post->id,
            'user_id' => $commenter->id,
            'username' => $commenter->name,
            'comment' => 'nice',
        ]);
        return [$post, $comment];
    }

    public function test_reacting_to_a_comment_notifies_the_commenter_but_not_when_reacting_to_your_own(): void
    {
        $postOwner = User::factory()->create();
        $commenter = User::factory()->create();
        $reactor = User::factory()->create();
        [$post, $comment] = $this->makeComment($postOwner, $commenter);

        Sanctum::actingAs($reactor);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();
        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $commenter->id,
            'type' => 'comment_reaction',
        ]);

        Sanctum::actingAs($commenter);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();
        $this->assertDatabaseMissing('notifications', [
            'user_id' => (string) $commenter->id,
            'type' => 'comment_reaction',
            'data->reactedByUserId' => (string) $commenter->id,
        ]);
    }

    public function test_reacting_twice_from_the_same_user_does_not_duplicate(): void
    {
        $postOwner = User::factory()->create();
        $commenter = User::factory()->create();
        $reactor = User::factory()->create();
        [$post, $comment] = $this->makeComment($postOwner, $commenter);

        Sanctum::actingAs($reactor);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();
        $response = $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions");

        $response->assertOk()->assertJsonPath('reactionsCount', 1);
        $this->assertSame(1, \App\Models\CommentReaction::query()
            ->where('note_comment_id', $comment->id)->where('user_id', $reactor->id)->count());
    }

    public function test_removing_a_reaction_updates_the_count(): void
    {
        $postOwner = User::factory()->create();
        $commenter = User::factory()->create();
        $reactor = User::factory()->create();
        [$post, $comment] = $this->makeComment($postOwner, $commenter);

        Sanctum::actingAs($reactor);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();
        $response = $this->deleteJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions");

        $response->assertOk()->assertJsonPath('reactionsCount', 0)->assertJsonPath('reactedByMe', false);
    }

    public function test_comment_listing_reflects_reaction_count_and_whether_the_viewer_reacted(): void
    {
        $postOwner = User::factory()->create();
        $commenter = User::factory()->create();
        $fan = User::factory()->create();
        $bystander = User::factory()->create();
        [$post, $comment] = $this->makeComment($postOwner, $commenter);

        Sanctum::actingAs($fan);
        $this->postJson("/api/community/posts/{$post->id}/comments/{$comment->id}/reactions")->assertOk();

        Sanctum::actingAs($fan);
        $fanView = $this->getJson("/api/community/posts/{$post->id}/comments");
        $fanComment = collect($fanView->json('comments'))->firstWhere('id', (string) $comment->id);
        $this->assertSame(1, $fanComment['reactionsCount']);
        $this->assertTrue($fanComment['reactedByMe']);

        Sanctum::actingAs($bystander);
        $bystanderView = $this->getJson("/api/community/posts/{$post->id}/comments");
        $bystanderComment = collect($bystanderView->json('comments'))->firstWhere('id', (string) $comment->id);
        $this->assertSame(1, $bystanderComment['reactionsCount']);
        $this->assertFalse($bystanderComment['reactedByMe']);
    }
}
