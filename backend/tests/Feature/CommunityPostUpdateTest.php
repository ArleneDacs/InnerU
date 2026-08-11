<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\CommunityPostHeart;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommunityPostUpdateTest extends TestCase
{
    use RefreshDatabase;

    private function makePost(User $owner): CommunityPost
    {
        return CommunityPost::create([
            'user_id' => $owner->id,
            'username' => $owner->name,
            'title' => 'Original title',
            'note' => [
                ['type' => 'text', 'value' => 'Original post body'],
                ['type' => 'image', 'value' => 'https://example.test/photo.jpg'],
            ],
            'color' => 0xFFABCDEF,
            'category' => 'Add Value',
            'saved' => false,
        ]);
    }

    public function test_owner_can_edit_post_content_without_losing_hearts_or_comments(): void
    {
        $owner = User::factory()->create();
        $fan = User::factory()->create();
        $post = $this->makePost($owner);
        CommunityPostHeart::create([
            'community_post_id' => $post->id,
            'user_id' => $fan->id,
        ]);
        $comment = NoteComment::create([
            'community_post_id' => $post->id,
            'user_id' => $fan->id,
            'username' => $fan->name,
            'comment' => 'Keeping this comment.',
        ]);

        Sanctum::actingAs($owner);
        $response = $this->patchJson('/api/community/posts/'.$post->id, [
            'title' => 'Edited title',
            'category' => 'Learning',
            'note' => [
                ['type' => 'text', 'value' => 'Edited post body'],
                ['type' => 'image', 'value' => 'https://example.test/photo.jpg'],
            ],
        ]);

        $response->assertOk()
            ->assertJsonPath('post.id', (string) $post->id)
            ->assertJsonPath('post.title', 'Edited title')
            ->assertJsonPath('post.category', 'Learning')
            ->assertJsonPath('post.note.0.value', 'Edited post body')
            ->assertJsonPath('post.heartsCount', 1);

        $this->assertDatabaseHas('community_post_hearts', [
            'community_post_id' => $post->id,
            'user_id' => $fan->id,
        ]);
        $this->assertDatabaseHas('note_comments', [
            'id' => $comment->id,
            'community_post_id' => $post->id,
        ]);
    }

    public function test_a_member_cannot_edit_someone_elses_post(): void
    {
        $owner = User::factory()->create();
        $otherMember = User::factory()->create();
        $post = $this->makePost($owner);

        Sanctum::actingAs($otherMember);
        $response = $this->patchJson('/api/community/posts/'.$post->id, [
            'title' => 'Attempted rewrite',
        ]);

        $response->assertUnauthorized();
        $this->assertDatabaseHas('community_posts', [
            'id' => $post->id,
            'title' => 'Original title',
        ]);
    }
}
