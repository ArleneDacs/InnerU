<?php
// backend/app/Services/FirestoreImport/NotesImporter.php

namespace App\Services\FirestoreImport;

use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\User;
use Illuminate\Support\Carbon;

class NotesImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('notes') as $record) {
            $this->importNote($record['id'], $record['data']);
        }

        foreach ($this->reader->collectionGroup('comments') as $record) {
            if (! str_starts_with($record['path'], 'notes/')) {
                continue; // 'goals/{id}/comments' belongs to GoalImporter
            }

            $segments = explode('/', $record['path']);
            $firestoreNoteId = $segments[1] ?? null;
            if ($firestoreNoteId === null) {
                $this->report->skip('note_comments', $record['id'], 'could not parse parent note id from path '.$record['path']);

                continue;
            }
            $this->importComment($firestoreNoteId, $record['data'], $record['id']);
        }
    }

    private function importNote(string $firestoreId, array $data): void
    {
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        if ($userId === null) {
            $this->report->skip('community_posts', $firestoreId, 'no matching user for userId '.($data['userId'] ?? 'null'));

            return;
        }

        $post = CommunityPost::where('firestore_id', $firestoreId)->first() ?? new CommunityPost();
        $post->firestore_id = $firestoreId;
        $post->user_id = $userId;
        $post->username = $data['username'] ?? '';
        $post->title = $data['title'] ?? '';
        $post->note = $data['note'] ?? [];

        $color = (int) ($data['color'] ?? 0xFFFFFFFF);
        $post->color = $color < 0 ? $color + 4294967296 : $color; // Dart packs ARGB as a signed 32-bit int

        $post->category = $data['category'] ?? '';
        $post->saved = $data['saved'] ?? false;
        $post->company_id = $data['companyId'] ?? null;
        $post->company_code = $data['companyCode'] ?? null;
        $post->company_name = $data['companyName'] ?? null;

        if (! empty($data['createdAt'])) {
            $post->timestamps = false;
            $post->created_at = Carbon::parse($data['createdAt']);
            $post->updated_at = $post->created_at;
        }

        $post->save();

        $this->report->increment('community_posts', $post->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importComment(string $firestoreNoteId, array $data, string $firestoreId): void
    {
        $postId = CommunityPost::where('firestore_id', $firestoreNoteId)->value('id');
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        if ($postId === null || $userId === null) {
            $this->report->skip('note_comments', $firestoreId, 'missing post or user match');

            return;
        }

        $comment = NoteComment::where('firestore_id', $firestoreId)->first() ?? new NoteComment();
        $comment->firestore_id = $firestoreId;
        $comment->community_post_id = $postId;
        $comment->user_id = $userId;
        $comment->username = $data['username'] ?? '';
        $comment->comment = $data['content'] ?? '';
        $comment->save();

        $this->report->increment('note_comments', $comment->wasRecentlyCreated ? 'created' : 'updated');
    }
}
