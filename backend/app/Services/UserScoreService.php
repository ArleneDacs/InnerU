<?php

namespace App\Services;

use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\Goal;
use App\Models\GoalTask;
use App\Models\User;
use App\Models\UserPoint;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

class UserScoreService
{
    /**
     * @var array<int, string>
     */
    private const DEFAULT_DAILY_TRACKER_IDS = [
        'call',
        'steps',
        'exercise',
        'meditation',
        'learning',
        'addValue',
    ];

    public function resolveForUser(User $user): float
    {
        return $this->resolveBreakdownForUser($user)['overallScore'];
    }

    /**
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    public function resolveBreakdownForUser(User $user): array
    {
        $goalScore = $this->resolveGoalScoreForUser($user);
        $company = $this->resolveCompaniesForUsers(collect([$user]))[(string) $user->id] ?? null;
        if ($this->hasConfiguredPeriod($company)) {
            // A leaderboard period must exclude everything before its start
            // date, including goals — the new Goals-based score is a single
            // date-independent value (all of a user's current goals,
            // regardless of when they started), so it isn't passed here.
            // The period path falls back to the per-day legacy todo-list
            // score instead, which is already correctly date-bounded since
            // it only reads DailyTracker rows within the period.
            return $this->scoreBreakdownForPeriod(
                $user,
                $company->leaderboard_period_start,
                $company->leaderboard_period_end,
            );
        }

        $trackers = DailyTracker::query()
            ->where('user_id', $user->id)
            ->orderBy('date')
            ->orderByDesc('updated_at')
            ->get([
                'user_id',
                'date',
                'step_count',
                'step_goal',
                'meditation',
                'steps',
                'call',
                'exercise',
                'learning',
                'add_value',
                'todo_list',
                'call_count',
                'exercise_count',
                'exercise_minutes',
                'learning_count',
                'value_count',
                'todo_list_count',
                'todo_list_score',
                'todo_list_score_daily_contribution',
                'todo_list_included_in_total',
                'user_total_score',
                'custom_daily_tasks',
                'meditation_minutes',
                'company_id',
                'company_code',
                'company_name',
                'updated_at',
            ]);

        if ($trackers->isNotEmpty()) {
            return $this->summarizeBreakdowns(
                $trackers
                    ->map(fn (DailyTracker $tracker) => $this->scoreBreakdownFromDailyTracker($user, $tracker, $goalScore))
                    ->all(),
                $user
            );
        }

        $points = UserPoint::query()
            ->where('user_id', $user->id)
            ->orderBy('date')
            ->orderByDesc('updated_at')
            ->get([
                'total_points',
                'activity_points',
                'daily_tracker_score',
                'todo_list_score',
                'todo_list_score_daily_contribution',
                'todo_list_included_in_total',
                'user_total_score',
                'updated_at',
            ]);

        if ($points->isNotEmpty()) {
            return $this->summarizeBreakdowns(
                $points
                    ->map(fn (UserPoint $point) => $this->scoreBreakdownFromUserPoint($point, $goalScore))
                    ->all(),
                $user
            );
        }

        if ($goalScore !== null) {
            return [
                'goalScore' => $goalScore,
                'coreTaskScore' => 0.0,
                'overallScore' => $goalScore,
            ];
        }

        $score = (float) ($user->score ?? 0);
        return [
            'goalScore' => $score,
            'coreTaskScore' => 0.0,
            'overallScore' => $score,
        ];
    }

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, float>
     */
    public function resolveForUsers(Collection $users): array
    {
        $details = $this->resolveBreakdownForUsers($users);

        return array_map(
            static fn (array $item) => $item['overallScore'],
            $details,
        );
    }

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, array{goalScore:float, coreTaskScore:float, overallScore:float}>
     */
    public function resolveBreakdownForUsers(Collection $users): array
    {
        $userIds = $users
            ->pluck('id')
            ->map(static fn ($id) => (string) $id)
            ->filter()
            ->values()
            ->all();

        if ($userIds === []) {
            return [];
        }

        $companiesByUser = $this->resolveCompaniesForUsers($users);
        $goalScoresByUser = $this->resolveGoalScoresForUsers($users);

        $scores = [];
        $periodUserIds = [];

        foreach ($users as $user) {
            $userId = (string) $user->id;
            $company = $companiesByUser[$userId] ?? null;

            if ($this->hasConfiguredPeriod($company)) {
                // See resolveBreakdownForUser: the period path deliberately
                // does not receive $goalScore, so it falls back to the
                // per-day legacy todo-list score instead of the
                // date-independent Goals-based score.
                $scores[$userId] = $this->scoreBreakdownForPeriod(
                    $user,
                    $company->leaderboard_period_start,
                    $company->leaderboard_period_end,
                );
                $periodUserIds[] = $userId;
            }
        }

        $remainingUsers = $users->reject(
            fn (User $user) => in_array((string) $user->id, $periodUserIds, true)
        );

        if ($remainingUsers->isEmpty()) {
            return $scores;
        }

        $remainingUserIds = $remainingUsers
            ->pluck('id')
            ->map(static fn ($id) => (string) $id)
            ->values()
            ->all();

        $trackerScores = $this->allTrackersByUserId(
            DailyTracker::query()
                ->whereIn('user_id', $remainingUserIds)
                ->orderBy('user_id')
                ->orderBy('date')
                ->orderByDesc('updated_at')
            ->get([
                    'user_id',
                    'date',
                    'step_count',
                    'step_goal',
                    'meditation',
                    'steps',
                    'call',
                    'exercise',
                    'learning',
                    'add_value',
                    'todo_list',
                    'call_count',
                    'exercise_count',
                    'exercise_minutes',
                    'learning_count',
                    'value_count',
                    'todo_list_count',
                    'todo_list_score',
                    'todo_list_score_daily_contribution',
                    'todo_list_included_in_total',
                    'user_total_score',
                    'custom_daily_tasks',
                    'meditation_minutes',
                    'company_id',
                    'company_code',
                    'company_name',
                    'updated_at',
                ])
        );

        $pointScores = $this->allPointsByUserId(
            UserPoint::query()
                ->whereIn('user_id', $remainingUserIds)
                ->orderBy('user_id')
                ->orderBy('date')
                ->orderByDesc('updated_at')
                ->get([
                    'user_id',
                    'total_points',
                    'activity_points',
                    'daily_tracker_score',
                    'todo_list_score',
                    'todo_list_score_daily_contribution',
                    'todo_list_included_in_total',
                    'user_total_score',
                    'updated_at',
                ])
        );

        foreach ($remainingUsers as $user) {
            $userId = (string) $user->id;
            $goalScore = $goalScoresByUser[$userId] ?? null;
            if (isset($trackerScores[$userId])) {
                $scores[$userId] = $this->summarizeBreakdowns(
                    $trackerScores[$userId]
                        ->map(fn (DailyTracker $tracker) => $this->scoreBreakdownFromDailyTracker($user, $tracker, $goalScore))
                        ->all(),
                    $user
                );
                continue;
            }

            if (isset($pointScores[$userId])) {
                $scores[$userId] = $this->summarizeBreakdowns(
                    $pointScores[$userId]
                        ->map(fn (UserPoint $point) => $this->scoreBreakdownFromUserPoint($point, $goalScore))
                        ->all(),
                    $user
                );
                continue;
            }

            if ($goalScore !== null) {
                $scores[$userId] = [
                    'goalScore' => $goalScore,
                    'coreTaskScore' => 0.0,
                    'overallScore' => $goalScore,
                ];
                continue;
            }

            $score = (float) ($user->score ?? 0);
            $scores[$userId] = [
                'goalScore' => $score,
                'coreTaskScore' => 0.0,
                'overallScore' => $score,
            ];
        }

        return $scores;
    }

    public function syncForUser(User $user, ?float $score = null): int
    {
        $resolvedScore = $this->normalizeScore($score ?? $this->resolveForUser($user));

        User::query()
            ->whereKey($user->id)
            ->update(['score' => $resolvedScore]);

        return $resolvedScore;
    }

    public function syncFromPayload(User $user, array $payload): int
    {
        return $this->syncForUser($user);
    }

    /**
     * @param  Collection<int, DailyTracker>  $records
     * @return array<string, Collection<int, DailyTracker>>
     */
    private function allTrackersByUserId(Collection $records): array
    {
        $scores = [];

        foreach ($records as $record) {
            $userId = (string) $record->user_id;
            $scores[$userId] ??= collect();
            $scores[$userId]->push($record);
        }

        return $scores;
    }

    /**
     * @param  Collection<int, UserPoint>  $records
     * @return array<string, Collection<int, UserPoint>>
     */
    private function allPointsByUserId(Collection $records): array
    {
        $scores = [];

        foreach ($records as $record) {
            $userId = (string) $record->user_id;
            $scores[$userId] ??= collect();
            $scores[$userId]->push($record);
        }

        return $scores;
    }

    /**
     * @param  array<int, array{goalScore:float, coreTaskScore:float, overallScore:float}>  $breakdowns
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    private function summarizeBreakdowns(array $breakdowns, User $user): array
    {
        if ($breakdowns === []) {
            $score = (float) ($user->score ?? 0);
            return [
                'goalScore' => $score,
                'coreTaskScore' => 0.0,
                'overallScore' => $score,
            ];
        }

        // Leaderboard score should not reset to a single day's completion.
        // Add up goalScore and coreTaskScore across every recorded day and
        // divide by the number of days, so the score is a running average
        // instead of snapping to whatever today's (possibly still-empty)
        // tracker row looks like.
        $count = count($breakdowns);
        $goalScoreTotal = 0.0;
        $coreTaskScoreTotal = 0.0;

        foreach ($breakdowns as $breakdown) {
            $goalScoreTotal += (float) ($breakdown['goalScore'] ?? 0);
            $coreTaskScoreTotal += (float) ($breakdown['coreTaskScore'] ?? 0);
        }

        $goalScore = $goalScoreTotal / $count;
        $coreTaskScore = $coreTaskScoreTotal / $count;
        $overallScore = ($goalScore + $coreTaskScore) / 2;

        return [
            'goalScore' => $goalScore,
            'coreTaskScore' => $coreTaskScore,
            'overallScore' => $overallScore,
        ];
    }

    private function normalizeScore(mixed $score): int
    {
        if ($score === null || $score === '' || is_bool($score)) {
            return 0;
        }

        return max(0, min(100, (int) round((float) $score)));
    }

    /**
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    private function scoreBreakdownFromDailyTracker(
        User $user,
        DailyTracker $tracker,
        ?float $goalScore = null
    ): array
    {
        $dailyTrackerIds = $this->dailyTrackerIdsForUser($user);
        $completedCount = 0;

        foreach ($dailyTrackerIds as $taskId) {
            if ($this->dailyTrackerTaskCompleted($tracker, $taskId)) {
                $completedCount++;
            }
        }

        $dailyTrackerScore = count($dailyTrackerIds) > 0
            ? (($completedCount / count($dailyTrackerIds)) * 100)
            : (float) ($tracker->user_total_score ?? 0);

        $resolvedGoalScore = $goalScore ?? $this->legacyGoalScoreFromTracker($tracker);
        $effectiveGoalScore = $resolvedGoalScore > 0
            ? $resolvedGoalScore
            : (float) $tracker->todo_list_score_daily_contribution;
        $includeTodoListScore = $goalScore !== null
            || (bool) $tracker->todo_list_included_in_total
            || $resolvedGoalScore > 0
            || $tracker->todo_list_score_daily_contribution > 0;

        $resolved = $includeTodoListScore
            ? (($dailyTrackerScore + $effectiveGoalScore) / 2)
            : $dailyTrackerScore;

        if ($resolved <= 0) {
            $resolved = (float) ($tracker->user_total_score ?? 0);
        }

        return [
            'goalScore' => $resolvedGoalScore,
            'coreTaskScore' => $dailyTrackerScore,
            'overallScore' => $resolved,
        ];
    }

    /**
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    private function scoreBreakdownFromUserPoint(
        UserPoint $point,
        ?float $goalScore = null
    ): array
    {
        $dailyTrackerScore = (float) $point->daily_tracker_score;
        $resolvedGoalScore = $goalScore ?? $this->legacyGoalScoreFromPoint($point);
        $effectiveGoalScore = $resolvedGoalScore > 0
            ? $resolvedGoalScore
            : (float) $point->todo_list_score_daily_contribution;

        if ($goalScore !== null
            || (bool) $point->todo_list_included_in_total
            || $resolvedGoalScore > 0
            || $point->todo_list_score_daily_contribution > 0
        ) {
            $resolved = (($dailyTrackerScore + $effectiveGoalScore) / 2);
            if ($resolved > 0) {
                return [
                    'goalScore' => $resolvedGoalScore,
                    'coreTaskScore' => $dailyTrackerScore,
                    'overallScore' => $resolved,
                ];
            }
        }

        if ($dailyTrackerScore > 0) {
            return [
                'goalScore' => $resolvedGoalScore,
                'coreTaskScore' => $dailyTrackerScore,
                'overallScore' => $dailyTrackerScore,
            ];
        }

        $resolved = (float) ($point->user_total_score ?: $point->total_points);
        return [
            'goalScore' => $resolvedGoalScore,
            'coreTaskScore' => $dailyTrackerScore,
            'overallScore' => $resolved,
        ];
    }

    /**
     * @return array<int, string>
     */
    private function dailyTrackerIdsForUser(User $user): array
    {
        $rawItems = $user->daily_tracker_items;
        if (! is_array($rawItems) || $rawItems === []) {
            return self::DEFAULT_DAILY_TRACKER_IDS;
        }

        $ids = [];
        foreach ($rawItems as $item) {
            $id = null;
            if (is_array($item)) {
                $id = $item['id'] ?? null;
            } elseif (is_object($item) && isset($item->id)) {
                $id = $item->id;
            }

            if (! is_string($id)) {
                continue;
            }

            $id = trim($id);
            if ($id === '' || $id === 'todoList') {
                continue;
            }

            $ids[] = $id;
        }

        return $ids === [] ? self::DEFAULT_DAILY_TRACKER_IDS : array_values(array_unique($ids));
    }

    private function dailyTrackerTaskCompleted(DailyTracker $tracker, string $taskId): bool
    {
        $customDailyTasks = $tracker->custom_daily_tasks;
        if (is_array($customDailyTasks) && isset($customDailyTasks[$taskId])) {
            $customTask = $customDailyTasks[$taskId];
            if (is_array($customTask)) {
                return ($customTask['completed'] ?? false) === true;
            }

            if (is_bool($customTask)) {
                return $customTask;
            }
        }

        $column = match ($taskId) {
            'addValue' => 'add_value',
            default => $taskId,
        };

        return (bool) $tracker->{$column};
    }

    private function activeCompanyValue(?string $primary, ?string $fallback): string
    {
        $value = trim((string) ($primary ?? ''));
        if ($value !== '') {
            return $value;
        }

        return trim((string) ($fallback ?? ''));
    }

    /**
     * @param  Collection<int, Company>  $companies
     */
    private function matchCompany(User $user, Collection $companies): ?Company
    {
        $companyId = $this->activeCompanyValue($user->active_company_id, $user->company_id);
        $companyCode = $this->activeCompanyValue($user->active_company_code, $user->company_code);
        $companyName = $this->activeCompanyValue($user->active_company_name, $user->company_name);

        return $companies->first(function (Company $company) use ($companyId, $companyCode, $companyName): bool {
            return ($companyId !== '' && (string) $company->id === $companyId)
                || ($companyCode !== '' && (string) $company->code === $companyCode)
                || ($companyName !== '' && (string) $company->name === $companyName);
        });
    }

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, Company>
     */
    private function resolveCompaniesForUsers(Collection $users): array
    {
        $ids = [];
        $codes = [];
        $names = [];

        foreach ($users as $user) {
            $ids[] = $this->activeCompanyValue($user->active_company_id, $user->company_id);
            $codes[] = $this->activeCompanyValue($user->active_company_code, $user->company_code);
            $names[] = $this->activeCompanyValue($user->active_company_name, $user->company_name);
        }

        $ids = array_values(array_unique(array_filter($ids)));
        $codes = array_values(array_unique(array_filter($codes)));
        $names = array_values(array_unique(array_filter($names)));

        if ($ids === [] && $codes === [] && $names === []) {
            return [];
        }

        $companies = Company::query()
            ->where(function ($builder) use ($ids, $codes, $names): void {
                if ($ids !== []) {
                    $builder->orWhereIn('id', $ids);
                }
                if ($codes !== []) {
                    $builder->orWhereIn('code', $codes);
                }
                if ($names !== []) {
                    $builder->orWhereIn('name', $names);
                }
            })
            ->get();

        $result = [];
        foreach ($users as $user) {
            $company = $this->matchCompany($user, $companies);
            if ($company !== null) {
                $result[(string) $user->id] = $company;
            }
        }

        return $result;
    }

    private function hasConfiguredPeriod(?Company $company): bool
    {
        return $company !== null
            && $company->leaderboard_period_start !== null
            && $company->leaderboard_period_end !== null;
    }

    /**
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    private function scoreBreakdownForPeriod(
        User $user,
        Carbon $start,
        Carbon $end,
        ?float $goalScore = null
    ): array
    {
        $trackers = DailyTracker::query()
            ->where('user_id', $user->id)
            ->whereBetween('date', [$start->toDateString(), $end->toDateString()])
            ->orderBy('date')
            ->get();

        $totalDays = $start->diffInDays($end) + 1;

        $coreTaskScoreSum = 0.0;
        $latestGoalScore = $goalScore;

        foreach ($trackers as $tracker) {
            $breakdown = $this->scoreBreakdownFromDailyTracker($user, $tracker, $goalScore);
            $coreTaskScoreSum += $breakdown['coreTaskScore'];
            // $trackers is ordered by date ascending, so the last
            // iteration holds the latest in-period record.
            $latestGoalScore = $breakdown['goalScore'];
        }

        if ($trackers->isEmpty()) {
            if ($latestGoalScore !== null) {
                return [
                    'goalScore' => (float) $latestGoalScore,
                    'coreTaskScore' => 0.0,
                    'overallScore' => (float) $latestGoalScore,
                ];
            }

            return [
                'goalScore' => 0.0,
                'coreTaskScore' => 0.0,
                'overallScore' => 0.0,
            ];
        }

        $coreTaskScore = $totalDays > 0 ? ($coreTaskScoreSum / $totalDays) : 0.0;
        $goalScoreValue = (float) ($latestGoalScore ?? 0);
        $overallScore = ($coreTaskScore + $goalScoreValue) / 2;

        return [
            'goalScore' => $goalScoreValue,
            'coreTaskScore' => $coreTaskScore,
            'overallScore' => $overallScore,
        ];
    }

    private function resolveGoalScoreForUser(User $user): ?float
    {
        return $this->resolveGoalScoresForUsers(collect([$user]))[(string) $user->id] ?? null;
    }

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, float>
     */
    private function resolveGoalScoresForUsers(Collection $users): array
    {
        $userIds = $users
            ->pluck('id')
            ->map(static fn ($id) => (string) $id)
            ->filter()
            ->values()
            ->all();

        if ($userIds === []) {
            return [];
        }

        $goals = Goal::query()
            ->whereIn('user_id', $userIds)
            ->orderBy('user_id')
            ->orderBy('category')
            ->orderBy('created_at')
            ->get([
                'id',
                'user_id',
                'category',
                'status',
                'goal_type',
                'progress',
                'target_value',
                'current_value',
            ]);

        if ($goals->isEmpty()) {
            return [];
        }

        $goalIds = $goals
            ->pluck('id')
            ->map(static fn ($id) => (string) $id)
            ->values()
            ->all();

        $tasksByGoalId = GoalTask::query()
            ->whereIn('goal_id', $goalIds)
            ->orderBy('sort_order')
            ->orderBy('created_at')
            ->get(['goal_id', 'status', 'sort_order'])
            ->groupBy(fn (GoalTask $task) => (string) $task->goal_id);

        $goalsByUserId = $goals->groupBy(fn (Goal $goal) => (string) $goal->user_id);
        $scores = [];

        foreach ($users as $user) {
            $userId = (string) $user->id;
            $userGoals = $goalsByUserId->get($userId, collect());
            if ($userGoals->isEmpty()) {
                continue;
            }

            $scores[$userId] = $this->scoreGoals($userGoals, $tasksByGoalId);
        }

        return $scores;
    }

    /**
     * @param  Collection<int, Goal>  $goals
     * @param  Collection<string, Collection<int, GoalTask>>  $tasksByGoalId
     */
    private function scoreGoals(Collection $goals, Collection $tasksByGoalId): float
    {
        $activeGoals = $goals->filter(
            fn (Goal $goal) => strtoupper((string) $goal->status) !== 'ABANDONED'
        );

        if ($goals->isNotEmpty() && $activeGoals->isEmpty()) {
            return 0.0;
        }

        $categoryScores = [];
        foreach (['PERSONAL', 'PROFESSIONAL', 'CONTRIBUTION'] as $category) {
            $goalScores = [];
            foreach ($activeGoals->filter(
                fn (Goal $goal) => strtoupper((string) $goal->category) === $category
            ) as $goal) {
                $score = $this->scoreGoal($goal, $tasksByGoalId->get((string) $goal->id, collect()));
                if ($score !== null) {
                    $goalScores[] = $score;
                }
            }

            $categoryScores[] = $goalScores === []
                ? 0.0
                : $this->roundOne(array_sum($goalScores) / count($goalScores));
        }

        return $this->roundOne(array_sum($categoryScores) / count($categoryScores));
    }

    /**
     * @param  Collection<int, GoalTask>  $tasks
     */
    private function scoreGoal(Goal $goal, Collection $tasks): ?float
    {
        $status = strtoupper((string) $goal->status);
        if ($status === 'ABANDONED') {
            return null;
        }

        if ($status === 'COMPLETED') {
            return 100.0;
        }

        $goalType = strtoupper((string) $goal->goal_type);
        if ($goalType === 'MILESTONE') {
            if ($tasks->isEmpty()) {
                return $this->clampScore((float) $goal->progress);
            }

            $weights = $tasks->map(
                fn (GoalTask $task) => $this->goalTaskStatusWeight((string) $task->status)
            )->all();

            return $this->roundOne(array_sum($weights) / count($weights));
        }

        $targetValue = (float) $goal->target_value;
        if ($targetValue > 0) {
            return $this->roundOne(
                $this->clampScore(((float) $goal->current_value / $targetValue) * 100)
            );
        }

        return $this->clampScore((float) $goal->progress);
    }

    private function legacyGoalScoreFromTracker(DailyTracker $tracker): float
    {
        return $tracker->todo_list_score > 0
            ? (float) $tracker->todo_list_score
            : (float) $tracker->todo_list_score_daily_contribution;
    }

    private function legacyGoalScoreFromPoint(UserPoint $point): float
    {
        return $point->todo_list_score > 0
            ? (float) $point->todo_list_score
            : (float) $point->todo_list_score_daily_contribution;
    }

    private function goalTaskStatusWeight(string $status): int
    {
        return match (strtoupper($status)) {
            'DONE' => 100,
            'IN_PROGRESS' => 50,
            default => 0,
        };
    }

    private function clampScore(float $score): float
    {
        return max(0.0, min(100.0, $score));
    }

    private function roundOne(float $score): float
    {
        return round($score * 10) / 10;
    }
}
