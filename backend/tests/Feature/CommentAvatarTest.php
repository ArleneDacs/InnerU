<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommentAvatarTest extends TestCase
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

    public function test_comment_response_includes_the_commenters_current_profile_pic(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create(['profile_pic' => 'https://cdn.example.com/avatar-v1.png']);
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'nice post',
        ]);

        $response->assertCreated()->assertJsonPath('comment.profilePic', 'https://cdn.example.com/avatar-v1.png');
    }

    public function test_avatar_reflects_a_later_profile_picture_change_without_editing_the_comment(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create(['profile_pic' => 'https://cdn.example.com/avatar-v1.png']);
        $post = $this->makePost($owner);

        $comment = NoteComment::create([
            'community_post_id' => $post->id,
            'user_id' => $commenter->id,
            'username' => $commenter->name,
            'comment' => 'nice post',
        ]);

        $commenter->update(['profile_pic' => 'https://cdn.example.com/avatar-v2.png']);

        Sanctum::actingAs($owner);
        $response = $this->getJson("/api/community/posts/{$post->id}/comments");

        $response->assertOk();
        $payload = collect($response->json('comments'))->firstWhere('id', $comment->id);
        $this->assertSame('https://cdn.example.com/avatar-v2.png', $payload['profilePic']);
    }

    public function test_missing_profile_pic_returns_null_not_an_error(): void
    {
        $owner = User::factory()->create();
        $commenter = User::factory()->create(['profile_pic' => null]);
        $post = $this->makePost($owner);

        Sanctum::actingAs($commenter);
        $response = $this->postJson("/api/community/posts/{$post->id}/comments", [
            'comment' => 'no avatar here',
        ]);

        $response->assertCreated()->assertJsonPath('comment.profilePic', null);
    }
}
