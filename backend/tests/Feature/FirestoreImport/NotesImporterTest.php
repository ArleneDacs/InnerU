<?php
// backend/tests/Feature/FirestoreImport/NotesImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\NotesImporter;
use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class NotesImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/notes-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_note_with_a_negative_packed_color_and_its_comments(): void
    {
        $author = User::factory()->create(['firebase_uid' => 'author-uid']);
        $commenter = User::factory()->create(['firebase_uid' => 'commenter-uid']);

        File::put("{$this->dir}/notes.json", json_encode([
            ['id' => 'note-1', 'data' => [
                'userId' => 'author-uid', 'username' => 'Author', 'title' => 'My journal entry',
                'note' => [['type' => 'text', 'value' => 'hello']], 'color' => -16777216, // 0xFF000000 as a signed 32-bit int
                'category' => 'journal', 'saved' => true, 'createdAt' => '2025-03-01T00:00:00.000Z',
            ]],
        ]));
        File::put("{$this->dir}/_group_comments.json", json_encode([
            ['id' => 'goal-cmt-1', 'path' => 'goals/goal-1/comments/goal-cmt-1', 'data' => ['authorId' => 'author-uid', 'body' => 'not a note comment']],
            ['id' => 'note-cmt-1', 'path' => 'notes/note-1/comments/note-cmt-1', 'data' => ['userId' => 'commenter-uid', 'username' => 'Commenter', 'content' => 'Nice post!']],
        ]));

        $importer = new NotesImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $post = CommunityPost::where('firestore_id', 'note-1')->first();
        $this->assertNotNull($post);
        $this->assertSame($author->id, $post->user_id);
        $this->assertSame(4278190080, $post->color); // 0xFF000000 as unsigned
        $this->assertSame('2025-03-01 00:00:00', $post->created_at->format('Y-m-d H:i:s'));

        $comment = NoteComment::where('firestore_id', 'note-cmt-1')->first();
        $this->assertNotNull($comment);
        $this->assertSame($post->id, $comment->community_post_id);
        $this->assertSame($commenter->id, $comment->user_id);
        $this->assertSame('Nice post!', $comment->comment);
        $this->assertSame(0, NoteComment::where('firestore_id', 'goal-cmt-1')->count(), 'goal comments must not leak into note_comments');
    }
}
