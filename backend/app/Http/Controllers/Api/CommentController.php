<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommunityPost;
use App\Models\NoteComment;
use App\Models\Notification;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
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
            ->with('user')
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
        $comment->load('user');

        // No self-notification when commenting on your own post.
        if ((string) $post->user_id !== (string) $user->id) {
            Notification::createFor(
                (string) $post->user_id,
                'community_comment',
                sprintf('%s commented on your post', $user->name),
                Str::limit(trim((string) $validated['comment']), 80),
                [
                    'postId' => (string) $post->id,
                    'commentId' => (string) $comment->id,
                    'commenterId' => (string) $user->id,
                ],
            );
        }

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
        $comment->refresh()->load('user');

        return response()->json(['comment' => $this->mapComment($comment)]);
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
            'profilePic' => $comment->user?->profile_pic,
            'comment' => $comment->comment,
            'createdAt' => $this->serializeAppDate($comment->created_at),
            'updatedAt' => $this->serializeAppDate($comment->updated_at),
        ];
    }

    private function serializeAppDate(?CarbonInterface $value): ?string
    {
        if ($value === null) {
            return null;
        }

        return CarbonImmutable::createFromFormat(
            'Y-m-d H:i:s.u',
            $value->format('Y-m-d H:i:s.u'),
            'UTC',
        )
            ->setTimezone(config('app.timezone', 'Asia/Manila'))
            ->toIso8601String();
    }
}
