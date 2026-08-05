<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommunityPost;
use App\Models\CommunityPostHeart;
use App\Models\User;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class CommunityController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $query = CommunityPost::query()->where(function ($query) use ($user): void {
            if ($user->company_code !== null && $user->company_code !== '') {
                $query->where('company_code', $user->company_code);
            }

            if ($user->company_name !== null && $user->company_name !== '') {
                $method = $user->company_code !== null && $user->company_code !== ''
                    ? 'orWhere'
                    : 'where';
                $query->{$method}('company_name', $user->company_name);
            }
        });

        if ($category = $request->string('category')->trim()->value()) {
            if ($category === 'Saved') {
                $query->where('saved', true)->where('user_id', $user->id);
            } elseif ($category === 'My Post') {
                $query->where('user_id', $user->id)->where('saved', false);
            } else {
                $query->where('category', $category)->where('saved', false);
            }
        }

        // One query for every heart this viewer has left, rather than an
        // exists() check per post below -- keeps this an O(1) query list
        // page regardless of how many posts are being returned.
        $heartedPostIds = CommunityPostHeart::query()
            ->where('user_id', $user->id)
            ->pluck('community_post_id')
            ->all();

        $posts = $query->withCount('hearts')->orderByDesc('created_at')->get()
            ->map(function (CommunityPost $post) use ($heartedPostIds) {
                return [
                    'id' => (string) $post->id,
                    'userId' => (string) $post->user_id,
                    'username' => $post->username,
                    'title' => $post->title,
                    'note' => $post->note,
                    'color' => $post->color,
                    'createdAt' => $this->serializeAppDate($post->created_at),
                    'category' => $post->category,
                    'saved' => $post->saved,
                    'companyId' => $post->company_id,
                    'companyCode' => $post->company_code,
                    'companyName' => $post->company_name,
                    'heartsCount' => (int) $post->hearts_count,
                    'heartedByMe' => in_array($post->id, $heartedPostIds, true),
                ];
            });

        return response()->json(['posts' => $posts]);
    }

    public function mentionableUsers(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $query = trim((string) $request->query('q', ''));

        if ($query === '') {
            return response()->json([]);
        }

        $companyCode = trim((string) ($user->active_company_code ?? $user->company_code ?? ''));
        $companyName = trim((string) ($user->active_company_name ?? $user->company_name ?? ''));

        $matches = User::query()
            ->where(function ($q) use ($companyCode, $companyName): void {
                if ($companyCode !== '') {
                    $q->where('company_code', $companyCode)
                        ->orWhere('active_company_code', $companyCode);
                }

                if ($companyName !== '') {
                    $q->orWhere('company_name', $companyName)
                        ->orWhere('active_company_name', $companyName);
                }
            })
            ->where('id', '!=', $user->id)
            ->where('name', 'ILIKE', "%{$query}%")
            ->orderBy('name')
            ->limit(10)
            ->get(['id', 'name', 'profile_pic']);

        return response()->json($matches->map(fn (User $u) => [
            'id' => (string) $u->id,
            'name' => $u->name,
            'profilePic' => $u->profile_pic,
        ])->values());
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'title' => ['required', 'string', 'max:255'],
            'category' => ['required', 'string', 'max:80'],
            'note' => ['required', 'array'],
            'color' => ['nullable', 'integer'],
            'saved' => ['nullable', 'boolean'],
        ]);

        $post = CommunityPost::create([
            'user_id' => $user->id,
            'username' => $user->name,
            'title' => $validated['title'],
            'note' => $validated['note'],
            'color' => $validated['color'] ?? 0xFFFFFFFF,
            'category' => $validated['category'],
            'saved' => (bool) ($validated['saved'] ?? false),
            'company_id' => $user->company_code,
            'company_code' => $user->company_code,
            'company_name' => $user->company_name,
        ]);

        return response()->json([
            'post' => $this->mapPost($post, (int) $user->id),
        ], Response::HTTP_CREATED);
    }

    public function update(Request $request, CommunityPost $post): JsonResponse
    {
        $user = $request->user();
        if ($user === null || (int) $post->user_id !== (int) $user->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'saved' => ['sometimes', 'boolean'],
        ]);

        $post->fill($validated);
        $post->save();

        return response()->json([
            'post' => $this->mapPost($post->refresh(), (int) $user->id),
        ]);
    }

    public function destroy(Request $request, CommunityPost $post): JsonResponse
    {
        $user = $request->user();
        if ($user === null || (int) $post->user_id !== (int) $user->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $post->delete();
        return response()->json(['message' => 'Deleted.']);
    }

    private function mapPost(CommunityPost $post, ?int $viewerId = null): array
    {
        $viewerId ??= (int) $post->user_id;

        return [
            'id' => (string) $post->id,
            'userId' => (string) $post->user_id,
            'username' => $post->username,
            'title' => $post->title,
            'note' => $post->note,
            'color' => $post->color,
            'createdAt' => $this->serializeAppDate($post->created_at),
            'category' => $post->category,
            'saved' => $post->saved,
            'companyId' => $post->company_id,
            'companyCode' => $post->company_code,
            'companyName' => $post->company_name,
            'heartsCount' => CommunityPostHeart::query()
                ->where('community_post_id', $post->id)
                ->count(),
            'heartedByMe' => CommunityPostHeart::query()
                ->where('community_post_id', $post->id)
                ->where('user_id', $viewerId)
                ->exists(),
        ];
    }

    private function serializeAppDate(?CarbonInterface $value): ?string
    {
        if ($value === null) {
            return null;
        }

        $timezone = (string) config('app.timezone', 'Asia/Manila');

        return CarbonImmutable::createFromFormat(
            'Y-m-d H:i:s.u',
            $value->format('Y-m-d H:i:s.u'),
            'UTC',
        )
            ->setTimezone($timezone)
            ->toIso8601String();
    }
}
