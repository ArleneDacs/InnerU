<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommunityPost;
use App\Models\CommunityPostHeart;
use App\Models\Notification;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class PostHeartController extends Controller
{
    public function store(Request $request, CommunityPost $post): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        // firstOrCreate on the unique (post, user) pair makes a repeat tap,
        // or a retried request, a no-op instead of a duplicate row --
        // wasRecentlyCreated then tells us whether *this* call is the one
        // that actually created the heart, which is what should gate the
        // "someone hearted your post" push below (so mashing the button
        // doesn't spam the owner with notifications).
        $heart = CommunityPostHeart::query()->firstOrCreate([
            'community_post_id' => $post->id,
            'user_id' => $user->id,
        ]);

        if ($heart->wasRecentlyCreated && (string) $post->user_id !== (string) $user->id) {
            Notification::createFor(
                (string) $post->user_id,
                'community_heart',
                sprintf('%s hearted your post', $user->name),
                null,
                [
                    'postId' => (string) $post->id,
                    'heartedByUserId' => (string) $user->id,
                ],
            );
        }

        return response()->json($this->heartState($post, (int) $user->id));
    }

    public function destroy(Request $request, CommunityPost $post): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        CommunityPostHeart::query()
            ->where('community_post_id', $post->id)
            ->where('user_id', $user->id)
            ->delete();

        return response()->json($this->heartState($post, (int) $user->id));
    }

    private function heartState(CommunityPost $post, int $userId): array
    {
        return [
            'postId' => (string) $post->id,
            'heartsCount' => CommunityPostHeart::query()
                ->where('community_post_id', $post->id)
                ->count(),
            'heartedByMe' => CommunityPostHeart::query()
                ->where('community_post_id', $post->id)
                ->where('user_id', $userId)
                ->exists(),
        ];
    }
}
