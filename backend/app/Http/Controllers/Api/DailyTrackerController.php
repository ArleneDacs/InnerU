<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\DailyTracker;
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

        $existingTracker = DailyTracker::query()
            ->where('user_id', $user->id)
            ->whereDate('date', $date)
            ->first();

        $customDailyTasks = $validated['custom_daily_tasks'] ?? $existingTracker?->custom_daily_tasks ?? [];
        if (! is_array($customDailyTasks)) {
            $customDailyTasks = [];
        }

        $tracker = DailyTracker::updateOrCreate(
            [
                'user_id' => $user->id,
                'date' => $date,
            ],
            [
                'username' => $validated['username'] ?? $existingTracker?->username ?? $user->name,
                'step_count' => $validated['step_count'] ?? $existingTracker?->step_count ?? 0,
                'step_goal' => $validated['step_goal'] ?? $existingTracker?->step_goal ?? 5000,
                'meditation' => $validated['meditation'] ?? $existingTracker?->meditation ?? false,
                'steps' => $validated['steps'] ?? $existingTracker?->steps ?? false,
                'call' => $validated['call'] ?? $existingTracker?->call ?? false,
                'exercise' => $validated['exercise'] ?? $existingTracker?->exercise ?? false,
                'learning' => $validated['learning'] ?? $existingTracker?->learning ?? false,
                'add_value' => $validated['add_value'] ?? $existingTracker?->add_value ?? false,
                'todo_list' => $validated['todo_list'] ?? $existingTracker?->todo_list ?? false,
                'call_count' => $validated['call_count'] ?? $existingTracker?->call_count ?? 0,
                'exercise_count' => $validated['exercise_count'] ?? $existingTracker?->exercise_count ?? 0,
                'exercise_minutes' => $validated['exercise_minutes'] ?? $existingTracker?->exercise_minutes ?? 0,
                'learning_count' => $validated['learning_count'] ?? $existingTracker?->learning_count ?? 0,
                'value_count' => $validated['value_count'] ?? $existingTracker?->value_count ?? 0,
                'todo_list_count' => $validated['todo_list_count'] ?? $existingTracker?->todo_list_count ?? 0,
                'todo_list_score' => $validated['todo_list_score'] ?? $existingTracker?->todo_list_score ?? 0,
                'todo_list_score_daily_contribution' => $validated['todo_list_score_daily_contribution'] ?? $existingTracker?->todo_list_score_daily_contribution ?? 0,
                'todo_list_included_in_total' => $validated['todo_list_included_in_total'] ?? $existingTracker?->todo_list_included_in_total ?? false,
                'user_total_score' => $validated['user_total_score'] ?? $existingTracker?->user_total_score ?? 0,
                'custom_daily_tasks' => $customDailyTasks,
                'meditation_minutes' => $validated['meditation_minutes'] ?? $existingTracker?->meditation_minutes ?? 0,
                'company_id' => $validated['company_id'] ?? $existingTracker?->company_id ?? $user->company_code,
                'company_code' => $validated['company_code'] ?? $existingTracker?->company_code ?? $user->company_code,
                'company_name' => $validated['company_name'] ?? $existingTracker?->company_name ?? $user->company_name,
            ]
        );

        $resolvedScore = $this->userScoreService->resolveForUser($user);
        $tracker->forceFill([
            'user_total_score' => $resolvedScore,
        ])->save();
        $this->userScoreService->syncForUser($user, $resolvedScore);

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

    private function activeCompanyValue(?string $primary, ?string $fallback): string
    {
        $value = trim((string) ($primary ?? ''));
        if ($value !== '') {
            return $value;
        }

        return trim((string) ($fallback ?? ''));
    }
}
