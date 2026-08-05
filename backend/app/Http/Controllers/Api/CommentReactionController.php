<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommentReaction;
use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CommentReactionController extends Controller
{
    public function store(Request $request, CommunityPost $post, NoteComment $comment): JsonResponse
    {
        $user = $request->user();
        abort_unless((int) $comment->community_post_id === (int) $post->id, 404);

        $reaction = CommentReaction::query()->firstOrCreate([
            'note_comment_id' => $comment->id,
            'user_id' => $user->id,
        ]);

        if ($reaction->wasRecentlyCreated && (string) $comment->user_id !== (string) $user->id) {
            Notification::createFor(
                (string) $comment->user_id,
                'comment_reaction',
                sprintf('%s reacted to your comment', $user->name),
                null,
                [
                    'postId' => (string) $post->id,
                    'commentId' => (string) $comment->id,
                    'reactedByUserId' => (string) $user->id,
                ],
            );
        }

        return response()->json($this->reactionState($comment, $user->id));
    }

    public function destroy(Request $request, CommunityPost $post, NoteComment $comment): JsonResponse
    {
        $user = $request->user();
        abort_unless((int) $comment->community_post_id === (int) $post->id, 404);

        CommentReaction::query()
            ->where('note_comment_id', $comment->id)
            ->where('user_id', $user->id)
            ->delete();

        return response()->json($this->reactionState($comment, $user->id));
    }

    private function reactionState(NoteComment $comment, int $userId): array
    {
        return [
            'commentId' => (string) $comment->id,
            'reactionsCount' => CommentReaction::query()->where('note_comment_id', $comment->id)->count(),
            'reactedByMe' => CommentReaction::query()
                ->where('note_comment_id', $comment->id)
                ->where('user_id', $userId)
                ->exists(),
        ];
    }
}
