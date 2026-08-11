<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommunityPost;
use App\Models\CommunityPostHeart;
use App\Models\Notification;
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
                    'mentions' => $post->mentions ?? [],
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

    /**
     * Resolve one post for a notification deep link without making the app
     * download every category just to find it.  Private saved posts remain
     * visible only to their owner.
     */
    public function show(Request $request, CommunityPost $post): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if (!$this->canViewPost($post, $user)) {
            // Returning Not Found avoids turning this endpoint into a way to
            // enumerate posts that belong to another company.
            return response()->json(['message' => 'Not found.'], Response::HTTP_NOT_FOUND);
        }

        return response()->json([
            'post' => $this->mapPost($post, (int) $user->id),
        ]);
    }

    /**
     * A paged, on-demand list for the heart-count popover.  It deliberately
     * is not embedded in the feed payload: a busy feed should not eagerly
     * transfer every name for every post when the vast majority are never
     * inspected.
     */
    public function hearts(Request $request, CommunityPost $post): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if (!$this->canViewPost($post, $user)) {
            return response()->json(['message' => 'Not found.'], Response::HTTP_NOT_FOUND);
        }

        // Keep every response small even if a popular post has thousands of
        // hearts.  The client can request the next page from its detail sheet.
        $requestedPerPage = (int) $request->query('perPage', 12);
        $perPage = min(25, max(1, $requestedPerPage));

        $hearts = CommunityPostHeart::query()
            ->where('community_post_id', $post->id)
            ->with('user:id,name')
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage);

        return response()->json([
            'likers' => $hearts->getCollection()
                ->map(fn (CommunityPostHeart $heart) => [
                    'id' => (string) $heart->user_id,
                    'name' => $heart->user?->name ?? 'Member',
                ])
                ->values(),
            'heartsCount' => (int) $hearts->total(),
            'page' => (int) $hearts->currentPage(),
            'perPage' => (int) $hearts->perPage(),
            'hasMore' => $hearts->hasMorePages(),
        ]);
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
            ->whereRaw('LOWER(name) LIKE ?', ['%' . strtolower($query) . '%'])
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
            'title' => ['required', 'string', 'max:50'],
            'category' => ['required', 'string', 'max:80'],
            'note' => ['required', 'array'],
            'color' => ['nullable', 'integer'],
            'saved' => ['nullable', 'boolean'],
            'mentions' => ['sometimes', 'nullable', 'array'],
            'mentions.*.userId' => ['required_with:mentions', 'string'],
            'mentions.*.name' => ['required_with:mentions', 'string'],
        ]);

        $mentions = $this->validateAndFilterMentions($validated['mentions'] ?? null, $user);

        $post = CommunityPost::create([
            'user_id' => $user->id,
            'username' => $user->name,
            'title' => $validated['title'],
            'note' => $validated['note'],
            'mentions' => $mentions,
            'color' => $validated['color'] ?? 0xFFFFFFFF,
            'category' => $validated['category'],
            'saved' => (bool) ($validated['saved'] ?? false),
            'company_id' => $user->company_code,
            'company_code' => $user->company_code,
            'company_name' => $user->company_name,
        ]);

        foreach ($mentions as $mention) {
            if ((string) $mention['userId'] === (string) $user->id) {
                continue;
            }
            Notification::createFor(
                (string) $mention['userId'],
                'community_mention',
                sprintf('%s mentioned you in a post', $user->name),
                null,
                ['postId' => (string) $post->id, 'mentionedByUserId' => (string) $user->id],
            );
        }

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
            'title' => ['sometimes', 'required', 'string', 'max:50'],
            'category' => ['sometimes', 'required', 'string', 'max:80'],
            'note' => ['sometimes', 'required', 'array'],
            'color' => ['sometimes', 'integer'],
            'saved' => ['sometimes', 'boolean'],
            'mentions' => ['sometimes', 'nullable', 'array'],
            'mentions.*.userId' => ['required_with:mentions', 'string'],
            'mentions.*.name' => ['required_with:mentions', 'string'],
        ]);

        // Only author-editable presentation fields are accepted here.  The
        // post id, owner, timestamps, hearts, and comments are deliberately
        // absent so an edit cannot disturb related data.
        $updates = array_intersect_key($validated, array_flip([
            'title',
            'category',
            'note',
            'color',
            'saved',
        ]));

        // Omitted mentions must stay intact (the simple edit dialog does not
        // alter them); an explicit mentions payload is still checked using
        // the same in-company validation as post creation.
        if (array_key_exists('mentions', $validated)) {
            $updates['mentions'] = $this->validateAndFilterMentions(
                $validated['mentions'],
                $user,
            );
        }

        $post->fill($updates);
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
            'mentions' => $post->mentions ?? [],
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

    /**
     * Match the feed's company visibility rules for the two targeted
     * endpoints above.  A post owner can always recover their own post from a
     * notification, while a saved post is never exposed to another member.
     */
    private function canViewPost(CommunityPost $post, User $viewer): bool
    {
        if ((int) $post->user_id === (int) $viewer->id) {
            return true;
        }

        if ($post->saved) {
            return false;
        }

        $companyCode = trim((string) $viewer->company_code);
        $companyName = trim((string) $viewer->company_name);

        // A user without company metadata currently sees the unfiltered feed
        // too, so preserve that established behaviour for a direct link.
        if ($companyCode === '' && $companyName === '') {
            return true;
        }

        return ($companyCode !== '' && (string) $post->company_code === $companyCode)
            || ($companyName !== '' && (string) $post->company_name === $companyName);
    }

    /**
     * Validate that every mentioned userId is a real user in the same
     * company as the author, then return the (unchanged) mentions array.
     * Aborts with 422 if any mentioned user can't be found in-company --
     * this is what prevents a client from using this to spam-notify or
     * fingerprint arbitrary users.
     *
     * @param  array<int, array<string, mixed>>|null  $mentions
     * @return array<int, array<string, mixed>>
     */
    private function validateAndFilterMentions(?array $mentions, User $author): array
    {
        if (empty($mentions)) {
            return [];
        }

        $companyCode = trim((string) ($author->active_company_code ?? $author->company_code ?? ''));
        $companyName = trim((string) ($author->active_company_name ?? $author->company_name ?? ''));

        $validIds = \App\Models\User::query()
            ->whereIn('id', collect($mentions)->pluck('userId'))
            ->where(function ($q) use ($companyCode, $companyName) {
                if ($companyCode !== '') {
                    $q->where('company_code', $companyCode)
                        ->orWhere('active_company_code', $companyCode);
                }

                if ($companyName !== '') {
                    $q->orWhere('company_name', $companyName)
                        ->orWhere('active_company_name', $companyName);
                }
            })
            ->pluck('id')
            ->map(fn ($id) => (string) $id)
            ->all();

        $filtered = collect($mentions)
            ->filter(fn ($m) => in_array((string) ($m['userId'] ?? ''), $validIds, true))
            ->values()
            ->all();

        if (count($filtered) !== count($mentions)) {
            abort(422, 'One or more mentioned users could not be found in your company.');
        }

        return $filtered;
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
