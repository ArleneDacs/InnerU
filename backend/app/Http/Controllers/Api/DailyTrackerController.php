<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\DailyTracker;
use App\Models\Notification;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Symfony\Component\HttpFoundation\Response;

class DailyTrackerController extends Controller
{
    public function __construct(private readonly UserScoreService $userScoreService)
    {
    }

    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'date' => ['nullable', 'date'],
        ]);

        $date = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : now()->toDateString();

        $tracker = DailyTracker::query()
            ->where('user_id', $user->id)
            ->whereDate('date', $date)
            ->first();

        return response()->json([
            'tracker' => $tracker ? $this->mapTracker($tracker) : null,
        ]);
    }

    public function history(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'month' => ['nullable', 'date_format:Y-m'],
        ]);

        $month = $validated['month'] ?? now()->format('Y-m');
        $parsed = Carbon::createFromFormat('Y-m', $month);

        $trackers = DailyTracker::query()
            ->where('user_id', $user->id)
            ->whereYear('date', $parsed->year)
            ->whereMonth('date', $parsed->month)
            ->orderBy('date')
            ->get()
            ->map(fn (DailyTracker $tracker) => $this->mapTracker($tracker))
            ->values();

        return response()->json([
            'trackers' => $trackers,
        ]);
    }

    public function friends(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'month' => ['nullable', 'date_format:Y-m'],
        ]);

        $month = $validated['month'] ?? now()->format('Y-m');
        $parsed = Carbon::createFromFormat('Y-m', $month);

        $companyId = $this->activeCompanyValue($user->active_company_id, $user->company_id);
        $companyCode = $this->activeCompanyValue($user->active_company_code, $user->company_code);
        $companyName = $this->activeCompanyValue($user->active_company_name, $user->company_name);

        $friendIds = $this->resolveFriendIds($user);
        if ($friendIds->isEmpty()) {
            $friendIds = $this->resolveCompanyPeerIds(
                companyId: $companyId,
                companyCode: $companyCode,
                companyName: $companyName,
                currentUserId: (string) $user->id,
            );
        }

        if ($friendIds->isEmpty()) {
            return response()->json([
                'friends' => [],
            ]);
        }

        $usersById = User::query()
            ->whereIn('id', $friendIds->all())
            ->get()
            ->keyBy(fn (User $friend) => (string) $friend->id);

        $trackers = DailyTracker::query()
            ->whereIn('user_id', $friendIds->all())
            ->whereYear('date', $parsed->year)
            ->whereMonth('date', $parsed->month)
            ->orderBy('date')
            ->get()
            ->groupBy(fn (DailyTracker $tracker) => (string) $tracker->user_id);

        $friends = $friendIds
            ->map(function (string $friendId) use ($usersById, $trackers): array {
                $user = $usersById->get($friendId);
                if ($user === null) {
                    return [];
                }

                $progress = [];
                foreach (($trackers->get($friendId) ?? collect()) as $tracker) {
                    $progress[$tracker->date?->toDateString() ?? now()->toDateString()] = $this->trackerPayload($tracker);
                }

                return [
                    'userId' => (string) $user->id,
                    'username' => $user->name,
                    'companyId' => $user->company_id,
                    'companyCode' => $user->company_code,
                    'companyName' => $user->company_name,
                    'progress' => $progress,
                ];
            })
            ->filter()
            ->values();

        return response()->json([
            'friends' => $friends,
        ]);
    }

    public function adminOverview(Request $request): JsonResponse
    {
        $admin = $request->user();
        if ($admin === null || ! $this->isAdmin($admin)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'month' => ['nullable', 'date_format:Y-m'],
        ]);

        $month = $validated['month'] ?? now()->format('Y-m');
        $parsed = Carbon::createFromFormat('Y-m', $month);
        $todayKey = now()->toDateString();

        $users = User::query()->orderBy('name')->get();

        $trackers = DailyTracker::query()
            ->whereYear('date', $parsed->year)
            ->whereMonth('date', $parsed->month)
            ->orderBy('date')
            ->get()
            ->groupBy(fn (DailyTracker $tracker) => (string) $tracker->user_id);

        $result = $users
            ->map(function (User $user) use ($trackers, $todayKey): array {
                $userId = (string) $user->id;
                $userTrackers = $trackers->get($userId) ?? collect();

                $progress = [];
                $todayTracker = null;
                foreach ($userTrackers as $tracker) {
                    $dateKey = $tracker->date?->toDateString();
                    if ($dateKey === null) {
                        continue;
                    }
                    $progress[$dateKey] = $this->trackerPayload($tracker);
                    if ($dateKey === $todayKey) {
                        $todayTracker = $tracker;
                    }
                }

                return [
                    'userId' => $userId,
                    'username' => $user->name,
                    'email' => $user->email,
                    'role' => $user->role,
                    'companyId' => $user->company_id,
                    'companyCode' => $user->company_code,
                    'companyName' => $user->company_name,
                    'todayCompletedCount' => $todayTracker
                        ? collect($this->trackerPayload($todayTracker))->filter()->count()
                        : 0,
                    'todayTaskCount' => count($this->trackerPayload($todayTracker ?? new DailyTracker())),
                    'todayUpdatedAt' => $todayTracker?->updated_at?->toIso8601String(),
                    'progress' => $progress,
                ];
            })
            ->values();

        return response()->json([
            'month' => $month,
            'date' => $todayKey,
            'users' => $result,
        ]);
    }

    public function upsert(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'date' => ['nullable', 'date'],
            'step_count' => ['nullable', 'integer', 'min:0'],
            'step_goal' => ['nullable', 'integer', 'min:1'],
            'meditation' => ['nullable', 'boolean'],
            'steps' => ['nullable', 'boolean'],
            'call' => ['nullable', 'boolean'],
            'exercise' => ['nullable', 'boolean'],
            'learning' => ['nullable', 'boolean'],
            'add_value' => ['nullable', 'boolean'],
            'todo_list' => ['nullable', 'boolean'],
            'call_count' => ['nullable', 'integer', 'min:0'],
            'exercise_count' => ['nullable', 'integer', 'min:0'],
            'exercise_minutes' => ['nullable', 'integer', 'min:0'],
            'learning_count' => ['nullable', 'integer', 'min:0'],
            'value_count' => ['nullable', 'integer', 'min:0'],
            'todo_list_count' => ['nullable', 'integer', 'min:0'],
            'todo_list_score' => ['nullable', 'integer', 'min:0'],
            'todo_list_score_daily_contribution' => ['nullable', 'integer', 'min:0'],
            'todo_list_included_in_total' => ['nullable', 'boolean'],
            'user_total_score' => ['nullable', 'integer', 'min:0'],
            'custom_daily_tasks' => ['nullable', 'array'],
            'meditation_minutes' => ['nullable', 'integer', 'min:0'],
            'username' => ['nullable', 'string', 'max:120'],
            'company_id' => ['nullable', 'string', 'max:120'],
            'company_code' => ['nullable', 'string', 'max:120'],
            'company_name' => ['nullable', 'string', 'max:120'],
        ]);

        $date = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : now()->toDateString();

        $tracker = DailyTracker::query()->firstOrCreate(
            [
                'user_id' => $user->id,
                'date' => $date,
            ],
            [
                'username' => $validated['username'] ?? $user->name,
                'custom_daily_tasks' => [],
                'company_id' => $validated['company_id'] ?? $user->company_code,
                'company_code' => $validated['company_code'] ?? $user->company_code,
                'company_name' => $validated['company_name'] ?? $user->company_name,
            ]
        );

        $wasRecentlyCreated = $tracker->wasRecentlyCreated;
        $requestToColumn = [
            'username' => 'username',
            'step_count' => 'step_count',
            'step_goal' => 'step_goal',
            'meditation' => 'meditation',
            'steps' => 'steps',
            'call' => 'call',
            'exercise' => 'exercise',
            'learning' => 'learning',
            'add_value' => 'add_value',
            'todo_list' => 'todo_list',
            'call_count' => 'call_count',
            'exercise_count' => 'exercise_count',
            'exercise_minutes' => 'exercise_minutes',
            'learning_count' => 'learning_count',
            'value_count' => 'value_count',
            'todo_list_count' => 'todo_list_count',
            'todo_list_score' => 'todo_list_score',
            'todo_list_score_daily_contribution' => 'todo_list_score_daily_contribution',
            'todo_list_included_in_total' => 'todo_list_included_in_total',
            'user_total_score' => 'user_total_score',
            'custom_daily_tasks' => 'custom_daily_tasks',
            'meditation_minutes' => 'meditation_minutes',
            'company_id' => 'company_id',
            'company_code' => 'company_code',
            'company_name' => 'company_name',
        ];
        $updates = [];
        foreach ($requestToColumn as $requestField => $column) {
            if (array_key_exists($requestField, $validated)
                && $validated[$requestField] !== null) {
                $updates[$column] = $validated[$requestField];
            }
        }
        if (array_key_exists('custom_daily_tasks', $updates)) {
            $updates['custom_daily_tasks'] = json_encode(
                $updates['custom_daily_tasks'],
                JSON_THROW_ON_ERROR,
            );
        }

        // Only update fields present in this request. Writing a full snapshot
        // assembled from an earlier read lets an automatic activity save erase
        // manual checks that commit between that read and this update.
        if ($updates !== []) {
            DailyTracker::query()
                ->whereKey($tracker->getKey())
                ->update($updates);
            $tracker->refresh();
        }

        try {
            $resolvedScore = $this->userScoreService->syncForUser($user);
            $tracker->forceFill([
                'user_total_score' => $resolvedScore,
            ])->save();
        } catch (\Throwable $throwable) {
            report($throwable);
        }

        // Throttled: only notify on the first tracker row for this
        // user+date, not on every subsequent field edit within the same
        // day (upsert is called repeatedly as the mentee checks off
        // individual tasks).
        if ($wasRecentlyCreated) {
            foreach (CoachMentee::coachIdsForMentee((string) $user->id) as $coachId) {
                Notification::createFor(
                    $coachId,
                    'mentee_progress_logged',
                    sprintf('%s logged today\'s tracker', $user->name),
                    null,
                    [
                        'menteeId' => (string) $user->id,
                        'trackerId' => (string) $tracker->id,
                        'date' => $date,
                    ],
                );
            }
        }

        return response()->json([
            'tracker' => $this->mapTracker($tracker->refresh()),
        ]);
    }

    private function mapTracker(DailyTracker $tracker): array
    {
        return [
            'id' => (string) $tracker->id,
            'userId' => (string) $tracker->user_id,
            'username' => $tracker->username,
            'date' => $tracker->date?->toDateString(),
            'stepCount' => $tracker->step_count,
            'stepGoal' => $tracker->step_goal,
            'meditation' => $tracker->meditation,
            'steps' => $tracker->steps,
            'call' => $tracker->call,
            'exercise' => $tracker->exercise,
            'learning' => $tracker->learning,
            'addValue' => $tracker->add_value,
            'todoList' => $tracker->todo_list,
            'meditationMinutes' => $tracker->meditation_minutes,
            'callCount' => $tracker->call_count,
            'exerciseCount' => $tracker->exercise_count,
            'exerciseMinutes' => $tracker->exercise_minutes,
            'learningCount' => $tracker->learning_count,
            'valueCount' => $tracker->value_count,
            'todoListCount' => $tracker->todo_list_count,
            'todoListScore' => $tracker->todo_list_score,
            'todoListScoreDailyContribution' => $tracker->todo_list_score_daily_contribution,
            'todoListIncludedInTotal' => $tracker->todo_list_included_in_total,
            'userTotalScore' => $tracker->user_total_score,
            'customDailyTasks' => $tracker->custom_daily_tasks,
            'companyId' => $tracker->company_id,
            'companyCode' => $tracker->company_code,
            'companyName' => $tracker->company_name,
            'createdAt' => $tracker->created_at?->toIso8601String(),
            'updatedAt' => $tracker->updated_at?->toIso8601String(),
        ];
    }

    private function trackerPayload(DailyTracker $tracker): array
    {
        return [
            'Call' => (bool) $tracker->call,
            'Steps' => (bool) $tracker->steps,
            'Exercise' => (bool) $tracker->exercise,
            'Meditation' => (bool) $tracker->meditation,
            'Learning' => (bool) $tracker->learning,
            'Add Value' => (bool) $tracker->add_value,
        ];
    }

    /**
     * @return Collection<int, string>
     */
    private function resolveFriendIds(User $user): Collection
    {
        $friendIds = collect();

        if ($this->isCoach($user)) {
            $groupIds = CoachGroup::query()
                ->where('coach_id', (string) $user->id)
                ->pluck('id');

            if ($groupIds->isNotEmpty()) {
                $friendIds = $friendIds->merge(
                    CoachMentee::query()
                        ->where('coach_id', (string) $user->id)
                        ->whereIn('group_id', $groupIds->all())
                        ->pluck('mentee_id')
                );
            }

            $friendIds = $friendIds->merge(
                CoachMentee::query()
                    ->where('coach_id', (string) $user->id)
                    ->pluck('mentee_id')
            );
        } else {
            $relations = CoachMentee::query()
                ->where('mentee_id', (string) $user->id)
                ->get();

            $groupIds = $relations
                ->pluck('group_id')
                ->filter()
                ->map(fn ($groupId) => (string) $groupId)
                ->values();

            $coachIds = $relations
                ->pluck('coach_id')
                ->filter()
                ->map(fn ($coachId) => (string) $coachId)
                ->values();

            if ($groupIds->isNotEmpty()) {
                $query = CoachMentee::query()->whereIn('group_id', $groupIds->all());
                if ($coachIds->isNotEmpty()) {
                    $query->whereIn('coach_id', $coachIds->all());
                }
                $friendIds = $friendIds->merge($query->pluck('mentee_id'));
            }

            if ($coachIds->isNotEmpty()) {
                $friendIds = $friendIds->merge(
                    CoachMentee::query()
                        ->whereIn('coach_id', $coachIds->all())
                        ->pluck('mentee_id')
                );
            }
        }

        return $friendIds
            ->map(fn ($id) => trim((string) $id))
            ->filter()
            ->unique()
            ->reject(fn (string $id) => $id === (string) $user->id)
            ->values();
    }

    /**
     * @return Collection<int, string>
     */
    private function resolveCompanyPeerIds(
        string $companyId,
        string $companyCode,
        string $companyName,
        string $currentUserId,
    ): Collection {
        $query = User::query()->where('id', '!=', $currentUserId);

        $didFilter = false;
        if ($companyId !== '') {
            $query->where(function ($builder) use ($companyId): void {
                $builder->where('company_id', $companyId)
                    ->orWhere('active_company_id', $companyId);
            });
            $didFilter = true;
        }
        if ($companyCode !== '') {
            $query->where(function ($builder) use ($companyCode): void {
                $builder->where('company_code', $companyCode)
                    ->orWhere('active_company_code', $companyCode);
            });
            $didFilter = true;
        }
        if ($companyName !== '') {
            $query->where(function ($builder) use ($companyName): void {
                $builder->where('company_name', $companyName)
                    ->orWhere('active_company_name', $companyName);
            });
            $didFilter = true;
        }

        if (! $didFilter) {
            return collect();
        }

        return $query
            ->pluck('id')
            ->map(fn ($id) => (string) $id)
            ->values();
    }

    private function isCoach(User $user): bool
    {
        $role = strtolower(trim((string) $user->role));
        return $role === 'coach' || (bool) $user->is_coach;
    }

    private function isAdmin(User $user): bool
    {
        $role = strtolower(trim((string) $user->role));
        return $role === 'admin' || (bool) $user->is_admin;
    }

    private function activeCompanyValue(?string $primary, ?string $fallback): string
    {
        $value = trim((string) ($primary ?? ''));
        if ($value !== '') {
            return $value;
        }

        return trim((string) ($fallback ?? ''));
    }
}
