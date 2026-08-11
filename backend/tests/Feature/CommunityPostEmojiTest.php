<?php

namespace Tests\Feature;

use App\Models\CommunityPost;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CommunityPostEmojiTest extends TestCase
{
    use RefreshDatabase;

    public function test_community_posts_preserve_emoji_through_storage_and_api_serialization(): void
    {
        $author = User::factory()->create();
        $title = 'Mom’s Birthday 🎂🎉';
        $body = 'Celebrating with family today! 🥳❤️';

        Sanctum::actingAs($author);
        $created = $this->postJson('/api/community/posts', [
            'title' => $title,
            'category' => 'Add Value',
            'note' => [
                ['type' => 'text', 'value' => $body],
            ],
        ]);

        $created->assertCreated()
            ->assertJsonPath('post.title', $title)
            ->assertJsonPath('post.note.0.value', $body);

        $postId = $created->json('post.id');
        $post = CommunityPost::findOrFail($postId);
        $this->assertSame($title, $post->title);
        $this->assertSame($body, $post->note[0]['value']);

        $this->getJson('/api/community/posts/'.$postId)
            ->assertOk()
            ->assertJsonPath('post.title', $title)
            ->assertJsonPath('post.note.0.value', $body);

        $updatedTitle = 'Birthday plans 🎈';
        $updatedBody = 'Cake is ready! 🍰';
        $this->patchJson('/api/community/posts/'.$postId, [
            'title' => $updatedTitle,
            'note' => [
                ['type' => 'text', 'value' => $updatedBody],
            ],
        ])
            ->assertOk()
            ->assertJsonPath('post.title', $updatedTitle)
            ->assertJsonPath('post.note.0.value', $updatedBody);

        $post->refresh();
        $this->assertSame($updatedTitle, $post->title);
        $this->assertSame($updatedBody, $post->note[0]['value']);
    }
}
