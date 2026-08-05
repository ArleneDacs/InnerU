<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommentReplyTest extends TestCase
{
    use RefreshDatabase;

    private function makePost(User $owner): CommunityPost
    {
        return CommunityPost::create([
            'user_id' => $owner->id,
            'username' => $owner->name,
            'title' => 'Test post',
            'note' => [['type' => 'text', 'value' => 'hello']],
            'color' => 0xFFFFFFFF,
            'category' => 'General',
            'saved' => false,
        ]);
    }

    public function test_a_reply_is_created_with_the_parent_comment_id(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $replier = User::factory()->create();
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $parent = $this->postJson("/api/community/posts/{$post->id}/comments", ['comment' => 'top level'])->json();

        Sanctum::actingAs($replier);
        $reply = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'a reply',
            'parentId' => $parent['comment']['id'],
        ]);

        $reply->assertCreated()->assertJsonPath('comment.parentId', $parent['comment']['id']);
    }

    public function test_a_top_level_comment_has_a_null_parent_id(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$post->id}/comments", ['comment' => 'top level']);

        $response->assertCreated()->assertJsonPath('comment.parentId', null);
    }

    public function test_replying_notifies_the_parent_comments_author_but_not_when_replying_to_yourself(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $replier = User::factory()->create();
        $post = $this->makePost($owner);

        $parent = NoteComment::create([
            'community_post_id' => $post->id,
            'user_id' => $commenter->id,
            'username' => $commenter->name,
            'comment' => 'top level',
        ]);

        Sanctum::actingAs($replier);
        $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'a reply', 'parentId' => $parent->id,
        ])->assertCreated();
        $this->assertDatabaseHas('notifications', [
            'user_id' => (string) $commenter->id,
            'type' => 'comment_reply',
        ]);

        Sanctum::actingAs($commenter);
        $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'replying to myself', 'parentId' => $parent->id,
        ])->assertCreated();
        $this->assertDatabaseMissing('notifications', [
            'user_id' => (string) $commenter->id,
            'type' => 'comment_reply',
            'data->replierId' => (string) $commenter->id,
        ]);
    }

    public function test_a_parentid_pointing_to_a_comment_on_a_different_post_is_rejected(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $postA = $this->makePost($owner);
        $postB = $this->makePost($owner);

        $foreignComment = NoteComment::create([
            'community_post_id' => $postB->id,
            'user_id' => $owner->id,
            'username' => $owner->name,
            'comment' => 'on a different post',
        ]);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$postA->id}/comments", [
            'comment' => 'sneaky reply', 'parentId' => $foreignComment->id,
        ]);

        $response->assertStatus(422);
    }

    public function test_a_parentid_pointing_to_a_reply_instead_of_a_top_level_comment_is_rejected(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create();
        $replier = User::factory()->create();
        $secondReplier = User::factory()->create();
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $parent = $this->postJson("/api/community/posts/{$post->id}/comments", ['comment' => 'top level'])->json();

        Sanctum::actingAs($replier);
        $reply = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'a reply',
            'parentId' => $parent['comment']['id'],
        ])->json();

        Sanctum::actingAs($secondReplier);
        $response = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'a reply to a reply',
            'parentId' => $reply['comment']['id'],
        ]);

        $response->assertStatus(422);
    }
}
