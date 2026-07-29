<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CoachMentee;
use App\Models\Goal;
use App\Models\GoalComment;
use App\Models\GoalMerit;
use App\Models\GoalTask;
use App\Models\GoalUpdate;
use App\Models\Notification;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class GoalController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $this->currentUser($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $goals = Goal::query()
            ->where('user_id', $user->id)
            ->orderBy('target_date')
            ->orderBy('created_at')
            ->get()
            ->map(fn (Goal $goal) => $this->mapGoal($goal));

        return response()->json(['goals' => $goals]);
    }

    public function show(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        return response()->json(['goal' => $this->mapGoal($goal)]);
    }

    public function tasks(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $tasks = GoalTask::query()
            ->where('goal_id', $goal->id)
            ->orderBy('sort_order')
            ->orderBy('created_at')
            ->get()
            ->map(fn (GoalTask $task) => $this->mapTask($task));

        return response()->json(['tasks' => $tasks]);
    }

    public function updates(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $updates = GoalUpdate::query()
            ->where('goal_id', $goal->id)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (GoalUpdate $update) => $this->mapUpdate($update));

        return response()->json(['updates' => $updates]);
    }

    public function comments(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $comments = GoalComment::query()
            ->where('goal_id', $goal->id)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (GoalComment $comment) => $this->mapComment($comment));

        return response()->json(['comments' => $comments]);
    }

    public function merits(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $merits = GoalMerit::query()
            ->where('goal_id', $goal->id)
            ->orderByDesc('date')
            ->limit(30)
            ->get()
            ->map(fn (GoalMerit $merit) => $this->mapMerit($merit));

        return response()->json(['merits' => $merits]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $this->currentUser($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'category' => ['required', 'string', 'max:32'],
            'title' => ['required', 'string', 'max:255'],
            'description' => ['nullable', 'string', 'max:5000'],
            'notes' => ['nullable', 'string', 'max:5000'],
            'status' => ['nullable', 'string', 'max:32'],
            'goal_type' => ['nullable', 'string', 'max:32'],
            'direction' => ['nullable', 'string', 'max:32'],
            'target_value' => ['nullable', 'numeric', 'min:0'],
            'current_value' => ['nullable', 'numeric', 'min:0'],
            'unit' => ['nullable', 'string', 'max:120'],
            'target_period' => ['nullable', 'string', 'max:32'],
            'start_date' => ['nullable', 'date'],
            'target_date' => ['required', 'date'],
            'plan_titles' => ['nullable', 'array'],
            'plan_titles.*' => ['string', 'max:255'],
        ]);

        $goalType = strtoupper((string) ($validated['goal_type'] ?? 'MERIT'));
        $isMilestone = $goalType === 'MILESTONE';
        $targetValue = $isMilestone ? 0 : max(0, (float) ($validated['target_value'] ?? 0));
        $currentValue = $isMilestone ? 0 : max(0, (float) ($validated['current_value'] ?? 0));
        $status = strtoupper((string) ($validated['status'] ?? 'IN_PROGRESS'));
        $direction = $isMilestone ? 'GAIN' : strtoupper((string) ($validated['direction'] ?? 'GAIN'));
        $targetPeriod = $isMilestone ? 'NONE' : strtoupper((string) ($validated['target_period'] ?? 'NONE'));
        $startDate = Carbon::parse($validated['start_date'] ?? now())->toDateString();
        $targetDate = Carbon::parse($validated['target_date'])->toDateString();
        $progress = $this->progressForValues($status, $goalType, $targetValue, $currentValue, []);

        $goal = DB::transaction(function () use ($user, $validated, $goalType, $isMilestone, $targetValue, $currentValue, $status, $direction, $targetPeriod, $progress, $startDate, $targetDate): Goal {
            $goal = Goal::create([
                'id' => (string) Str::uuid(),
                'user_id' => $user->id,
                'company_id' => $this->activeCompanyValue($user->active_company_id, $user->company_id),
                'category' => strtoupper((string) $validated['category']),
                'title' => trim((string) $validated['title']),
                'description' => $validated['description'] ?? null,
                'notes' => $validated['notes'] ?? null,
                'status' => $status,
                'goal_type' => $goalType,
                'direction' => $direction,
                'target_value' => $targetValue,
                'current_value' => $currentValue,
                'unit' => $isMilestone ? null : trim((string) ($validated['unit'] ?? '')),
                'target_period' => $targetPeriod,
                'start_date' => $startDate,
                'target_date' => $targetDate,
                'completed_at' => $status === 'COMPLETED' ? now() : null,
                'progress' => $progress,
            ]);

            $planTitles = array_values(array_filter(array_map(
                static fn ($value) => trim((string) $value),
                $validated['plan_titles'] ?? [],
            )));

            foreach ($planTitles as $index => $title) {
                GoalTask::create([
                    'id' => (string) Str::uuid(),
                    'goal_id' => $goal->id,
                    'title' => $title,
                    'status' => 'NOT_STARTED',
                    'is_complete' => false,
                    'sort_order' => $index,
                    'weight' => 1,
                ]);
            }

            return $goal;
        });

        return response()->json([
            'goal' => $this->mapGoal($goal->refresh()),
        ], Response::HTTP_CREATED);
    }

    public function update(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'title' => ['sometimes', 'string', 'max:255'],
            'description' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'status' => ['sometimes', 'string', 'max:32'],
            'target_date' => ['sometimes', 'date'],
            'direction' => ['sometimes', 'nullable', 'string', 'max:32'],
            'target_value' => ['sometimes', 'nullable', 'numeric', 'min:0'],
            'current_value' => ['sometimes', 'nullable', 'numeric', 'min:0'],
            'unit' => ['sometimes', 'nullable', 'string', 'max:120'],
            'goal_type' => ['sometimes', 'string', 'max:32'],
            'target_period' => ['sometimes', 'nullable', 'string', 'max:32'],
            'start_date' => ['sometimes', 'nullable', 'date'],
        ]);

        $goalType = strtoupper((string) ($validated['goal_type'] ?? $goal->goal_type));
        $isMilestone = $goalType === 'MILESTONE';
        $statusFrom = $goal->status;
        $statusTo = strtoupper((string) ($validated['status'] ?? $goal->status));
        $progressFrom = (int) $goal->progress;
        $targetValue = $isMilestone
            ? 0
            : (float) ($validated['target_value'] ?? $goal->target_value);
        $currentValue = $isMilestone
            ? 0
            : (float) ($validated['current_value'] ?? $goal->current_value);
        $direction = $isMilestone
            ? 'GAIN'
            : strtoupper((string) ($validated['direction'] ?? $goal->direction));
        $targetPeriod = $isMilestone
            ? 'NONE'
            : strtoupper((string) ($validated['target_period'] ?? $goal->target_period));

        $progressTo = $this->progressForValues(
            $statusTo,
            $goalType,
            $targetValue,
            $currentValue,
            $goalType === 'MILESTONE' ? $this->taskWeights($goal->id) : []
        );

        DB::transaction(function () use ($goal, $user, $validated, $statusFrom, $statusTo, $progressFrom, $progressTo, $goalType, $targetValue, $currentValue, $direction, $targetPeriod): void {
            $goal->update([
                'title' => $validated['title'] ?? $goal->title,
                'description' => array_key_exists('description', $validated) ? $validated['description'] : $goal->description,
                'notes' => array_key_exists('notes', $validated) ? $validated['notes'] : $goal->notes,
                'status' => $statusTo,
                'start_date' => isset($validated['start_date'])
                    ? Carbon::parse($validated['start_date'])->toDateString()
                    : $goal->start_date?->toDateString(),
                'target_date' => isset($validated['target_date'])
                    ? Carbon::parse($validated['target_date'])->toDateString()
                    : $goal->target_date?->toDateString(),
                'direction' => $direction,
                'target_value' => $targetValue,
                'current_value' => $currentValue,
                'unit' => $goalType === 'MILESTONE'
                    ? null
                    : ($validated['unit'] ?? $goal->unit),
                'goal_type' => $goalType,
                'target_period' => $targetPeriod,
                'completed_at' => $statusTo === 'COMPLETED'
                    ? ($goal->completed_at ?? now())
                    : null,
                'progress' => $progressTo,
            ]);

            GoalUpdate::create([
                'id' => (string) Str::uuid(),
                'goal_id' => $goal->id,
                'author_id' => $user->id,
                'progress_from' => $progressFrom,
                'progress_to' => $progressTo,
                'status_from' => $statusFrom,
                'status_to' => $statusTo,
            ]);
        });

        return response()->json(['goal' => $this->mapGoal($goal->refresh())]);
    }

    public function updateMeasure(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'current_value' => ['required', 'numeric', 'min:0'],
        ]);

        if ($goal->goal_type !== 'MERIT') {
            return response()->json(['message' => 'Only merit goals have a measure.'], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $currentValue = max(0, (float) $validated['current_value']);
        $progressFrom = (int) $goal->progress;
        $statusFrom = $goal->status;
        $progressTo = $this->progressForValues(
            $goal->status,
            $goal->goal_type,
            (float) $goal->target_value,
            $currentValue,
            [],
        );

        DB::transaction(function () use ($goal, $currentValue, $progressFrom, $progressTo, $statusFrom): void {
            $goal->update([
                'current_value' => $currentValue,
                'progress' => $progressTo,
            ]);

            GoalUpdate::create([
                'id' => (string) Str::uuid(),
                'goal_id' => $goal->id,
                'author_id' => $goal->user_id,
                'progress_from' => $progressFrom,
                'progress_to' => $progressTo,
                'status_from' => $statusFrom,
                'status_to' => $statusFrom,
            ]);
        });

        return response()->json(['goal' => $this->mapGoal($goal->refresh())]);
    }

    public function storeTask(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'title' => ['required', 'string', 'max:255'],
        ]);

        $task = GoalTask::create([
            'id' => (string) Str::uuid(),
            'goal_id' => $goal->id,
            'title' => trim((string) $validated['title']),
            'status' => 'NOT_STARTED',
            'is_complete' => false,
            'sort_order' => GoalTask::query()->where('goal_id', $goal->id)->count(),
            'weight' => 1,
        ]);

        $this->syncMilestoneProgress($goal->refresh(), $user);

        return response()->json(['task' => $this->mapTask($task)], Response::HTTP_CREATED);
    }

    public function updateTaskStatus(Request $request, Goal $goal, GoalTask $task): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal) || (string) $task->goal_id !== (string) $goal->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'status' => ['required', 'string', 'max:32'],
        ]);

        $wasComplete = (bool) $task->is_complete;

        $task->update([
            'status' => strtoupper((string) $validated['status']),
            'is_complete' => strtoupper((string) $validated['status']) === 'DONE',
            'completed_at' => strtoupper((string) $validated['status']) === 'DONE' ? now() : null,
        ]);

        $this->syncMilestoneProgress($goal->refresh(), $user);

        // Throttled: only on the NOT complete -> complete transition, not on
        // every other status update and not when un-completing.
        if (! $wasComplete && $task->is_complete) {
            foreach (CoachMentee::coachIdsForMentee((string) $user->id) as $coachId) {
                Notification::createFor(
                    $coachId,
                    'mentee_progress_logged',
                    sprintf('%s completed a goal task', $user->name),
                    $task->title,
                    [
                        'menteeId' => (string) $user->id,
                        'goalId' => (string) $goal->id,
                        'goalTaskId' => (string) $task->id,
                    ],
                );
            }
        }

        return response()->json(['task' => $this->mapTask($task->refresh())]);
    }

    public function destroyTask(Request $request, Goal $goal, GoalTask $task): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal) || (string) $task->goal_id !== (string) $goal->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $task->delete();
        $this->syncMilestoneProgress($goal->refresh(), $user);

        return response()->json(['message' => 'Deleted.']);
    }

    public function storeComment(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'body' => ['required', 'string', 'max:5000'],
            'is_private' => ['sometimes', 'boolean'],
        ]);

        $comment = GoalComment::create([
            'id' => (string) Str::uuid(),
            'goal_id' => $goal->id,
            'author_id' => $user->id,
            'body' => trim((string) $validated['body']),
            'is_private' => (bool) ($validated['is_private'] ?? false),
        ]);

        return response()->json(['comment' => $this->mapComment($comment)], Response::HTTP_CREATED);
    }

    public function logMeritTarget(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if ($goal->goal_type !== 'MERIT') {
            return response()->json(['message' => 'Only merit goals have a recurring target.'], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $targetPeriod = strtoupper((string) $goal->target_period);
        if ($targetPeriod === 'NONE') {
            return response()->json(['message' => 'This goal has no recurring target.'], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $merits = GoalMerit::query()
            ->where('goal_id', $goal->id)
            ->orderByDesc('date')
            ->limit(10)
            ->pluck('date')
            ->map(fn ($value) => (string) $value)
            ->all();

        if ($this->periodLogged($merits, $targetPeriod)) {
            return response()->json(['message' => 'Already logged.']);
        }

        $targetDate = $goal->target_date?->toDateString() ?? now()->addDay()->toDateString();
        $daysRemaining = now()->startOfDay()
            ->diffInDays(Carbon::parse($targetDate)->startOfDay(), false);
        $daysRemaining = max(1, (int) $daysRemaining);
        $periodDays = $this->periodDays($targetPeriod);
        $amount = $this->perPeriodTarget(
            (float) $goal->target_value,
            (float) $goal->current_value,
            $daysRemaining,
            $periodDays
        );

        $this->addMerit($goal, $user, $amount);

        return response()->json(['goal' => $this->mapGoal($goal->refresh())]);
    }

    public function goExtraMile(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if ($goal->goal_type !== 'MERIT') {
            return response()->json(['message' => 'Only merit goals can log extra progress.'], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $validated = $request->validate([
            'amount' => ['required', 'numeric', 'min:0'],
        ]);

        $this->addMerit($goal, $user, (float) $validated['amount']);

        return response()->json(['goal' => $this->mapGoal($goal->refresh())]);
    }

    public function destroy(Request $request, Goal $goal): JsonResponse
    {
        $user = $this->currentUser($request);
        if (!$this->ownsGoal($user, $goal)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $goal->delete();

        return response()->json(['message' => 'Deleted.']);
    }

    private function addMerit(Goal $goal, User $user, float $amount): void
    {
        $amount = max(0, $amount);
        $progressFrom = (int) $goal->progress;
        $statusFrom = $goal->status;
        $currentValue = (float) $goal->current_value + $amount;
        $progressTo = $this->progressForValues(
            $goal->status,
            $goal->goal_type,
            (float) $goal->target_value,
            $currentValue,
            [],
        );

        DB::transaction(function () use ($goal, $user, $amount, $progressFrom, $progressTo, $statusFrom, $currentValue): void {
            GoalMerit::create([
                'id' => (string) Str::uuid(),
                'goal_id' => $goal->id,
                'user_id' => $user->id,
                'date' => now()->toDateString(),
                'amount' => $amount,
            ]);

            $goal->update([
                'current_value' => $currentValue,
                'progress' => $progressTo,
            ]);

            GoalUpdate::create([
                'id' => (string) Str::uuid(),
                'goal_id' => $goal->id,
                'author_id' => $user->id,
                'progress_from' => $progressFrom,
                'progress_to' => $progressTo,
                'status_from' => $statusFrom,
                'status_to' => $statusFrom,
            ]);
        });
    }

    private function syncMilestoneProgress(Goal $goal, User $user): void
    {
        if ($goal->goal_type !== 'MILESTONE' || $goal->status === 'COMPLETED') {
            return;
        }

        $weights = $this->taskWeights($goal->id);
        $progressFrom = (int) $goal->progress;
        $progressTo = $this->progressForValues(
            $goal->status,
            $goal->goal_type,
            (float) $goal->target_value,
            (float) $goal->current_value,
            $weights,
        );

        if ($progressFrom === $progressTo) {
            return;
        }

        DB::transaction(function () use ($goal, $user, $progressFrom, $progressTo): void {
            $goal->update(['progress' => $progressTo]);

            GoalUpdate::create([
                'id' => (string) Str::uuid(),
                'goal_id' => $goal->id,
                'author_id' => $user->id,
                'progress_from' => $progressFrom,
                'progress_to' => $progressTo,
                'status_from' => $goal->status,
                'status_to' => $goal->status,
            ]);
        });
    }

    private function taskWeights(string $goalId): array
    {
        return GoalTask::query()
            ->where('goal_id', $goalId)
            ->orderBy('sort_order')
            ->get()
            ->map(fn (GoalTask $task) => $this->statusWeight($task->status))
            ->all();
    }

    private function progressForValues(
        string $status,
        string $goalType,
        float $targetValue,
        float $currentValue,
        array $weights,
    ): int {
        if ($status === 'COMPLETED') {
            return 100;
        }

        if ($goalType === 'MILESTONE') {
            if ($weights === []) {
                return 0;
            }

            return (int) round(array_sum($weights) / count($weights));
        }

        if ($targetValue <= 0) {
            return 0;
        }

        return (int) round(min(100, max(0, ($currentValue / $targetValue) * 100)));
    }

    private function statusWeight(string $status): int
    {
        return match (strtoupper($status)) {
            'DONE' => 100,
            'IN_PROGRESS' => 50,
            default => 0,
        };
    }

    private function periodDays(string $period): int
    {
        return match ($period) {
            'DAILY' => 1,
            'EVERY_2' => 2,
            'EVERY_3' => 3,
            'EVERY_4' => 4,
            'EVERY_5' => 5,
            'EVERY_6' => 6,
            'WEEKLY' => 7,
            default => 0,
        };
    }

    private function periodLogged(array $logDays, string $period): bool
    {
        $days = $this->periodDays($period);
        if ($days <= 0) {
            return false;
        }

        $since = now()->startOfDay()->subDays(max(1, $days) - 1)->toDateString();

        foreach ($logDays as $day) {
            if ($day >= $since) {
                return true;
            }
        }

        return false;
    }

    private function perPeriodTarget(float $target, float $current, int $daysRemaining, int $periodDays): float
    {
        if ($periodDays <= 0) {
            return 0;
        }

        $periods = max(1, intdiv($daysRemaining, $periodDays));
        $remaining = max(0, $target - $current);

        return round(($remaining / $periods) * 100) / 100;
    }

    private function mapGoal(Goal $goal): array
    {
        return [
            'id' => (string) $goal->id,
            'userId' => (string) $goal->user_id,
            'companyId' => $goal->company_id,
            'title' => $goal->title,
            'description' => $goal->description,
            'notes' => $goal->notes,
            'status' => $goal->status,
            'progress' => (int) $goal->progress,
            'category' => $goal->category,
            'goalType' => $goal->goal_type,
            'targetPeriod' => $goal->target_period,
            'direction' => $goal->direction,
            'targetValue' => (float) $goal->target_value,
            'currentValue' => (float) $goal->current_value,
            'unit' => $goal->unit ?? '',
            'startDate' => $goal->start_date?->toIso8601String(),
            'targetDate' => $goal->target_date?->toIso8601String(),
            'completedAt' => $goal->completed_at?->toIso8601String(),
            'createdAt' => $goal->created_at?->toIso8601String(),
            'updatedAt' => $goal->updated_at?->toIso8601String(),
        ];
    }

    private function mapTask(GoalTask $task): array
    {
        return [
            'id' => (string) $task->id,
            'goalId' => (string) $task->goal_id,
            'title' => $task->title,
            'status' => $task->status,
            'isComplete' => $task->is_complete,
            'dueDate' => $task->due_date?->toIso8601String(),
            'completedAt' => $task->completed_at?->toIso8601String(),
            'sortOrder' => (int) $task->sort_order,
            'weight' => (int) $task->weight,
        ];
    }

    private function mapUpdate(GoalUpdate $update): array
    {
        return [
            'id' => (string) $update->id,
            'authorId' => (string) $update->author_id,
            'progressFrom' => (int) $update->progress_from,
            'progressTo' => (int) $update->progress_to,
            'statusFrom' => $update->status_from,
            'statusTo' => $update->status_to,
            'note' => $update->note,
            'createdAt' => $update->created_at?->toIso8601String(),
        ];
    }

    private function mapComment(GoalComment $comment): array
    {
        return [
            'id' => (string) $comment->id,
            'authorId' => (string) $comment->author_id,
            'body' => $comment->body,
            'isPrivate' => $comment->is_private,
            'createdAt' => $comment->created_at?->toIso8601String(),
            'updatedAt' => $comment->updated_at?->toIso8601String(),
        ];
    }

    private function mapMerit(GoalMerit $merit): array
    {
        return [
            'id' => (string) $merit->id,
            'date' => $merit->date?->toDateString(),
            'amount' => (float) $merit->amount,
        ];
    }

    private function currentUser(Request $request): ?User
    {
        $user = $request->user();
        return $user instanceof User ? $user : null;
    }

    private function ownsGoal(?User $user, Goal $goal): bool
    {
        return $user !== null && (int) $goal->user_id === (int) $user->id;
    }

    private function activeCompanyValue(?string $primary, ?string $fallback): ?string
    {
        $value = trim((string) ($primary ?? ''));
        if ($value !== '') {
            return $value;
        }

        $value = trim((string) ($fallback ?? ''));
        return $value === '' ? null : $value;
    }
}
