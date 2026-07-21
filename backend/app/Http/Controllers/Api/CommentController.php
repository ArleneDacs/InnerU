<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommunityPost;
use App\Models\NoteComment;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class CommentController extends Controller
{
    public function index(Request $request, CommunityPost $post): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $comments = NoteComment::query()
            ->where('community_post_id', $post->id)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (NoteComment $comment) => $this->mapComment($comment));

        return response()->json(['comments' => $comments]);
    }

    public function store(Request $request, CommunityPost $post): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'comment' => ['required', 'string', 'max:5000'],
        ]);

        $comment = NoteComment::create([
            'community_post_id' => $post->id,
            'user_id' => $user->id,
            'username' => $user->name,
            'comment' => $validated['comment'],
        ]);

        return response()->json([
            'comment' => $this->mapComment($comment),
        ], Response::HTTP_CREATED);
    }

    public function update(Request $request, CommunityPost $post, NoteComment $comment): JsonResponse
    {
        $user = $request->user();
        if (
            $user === null ||
            (int) $comment->user_id !== (int) $user->id ||
            (int) $comment->community_post_id !== (int) $post->id
        ) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'comment' => ['required', 'string', 'max:5000'],
        ]);

        $comment->update(['comment' => $validated['comment']]);

        return response()->json(['comment' => $this->mapComment($comment->refresh())]);
    }

    public function destroy(Request $request, CommunityPost $post, NoteComment $comment): JsonResponse
    {
        $user = $request->user();
        if (
            $user === null ||
            (int) $comment->user_id !== (int) $user->id ||
            (int) $comment->community_post_id !== (int) $post->id
        ) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $comment->delete();

        return response()->json(['message' => 'Deleted.']);
    }

    private function mapComment(NoteComment $comment): array
    {
        return [
            'id' => (string) $comment->id,
            'postId' => (string) $comment->community_post_id,
            'userId' => (string) $comment->user_id,
            'username' => $comment->username,
            'comment' => $comment->comment,
            'createdAt' => $comment->created_at?->toIso8601String(),
            'updatedAt' => $comment->updated_at?->toIso8601String(),
        ];
    }
}
