<?php

namespace App\Services;

use App\Models\DailyTracker;
use App\Models\User;
use App\Models\UserPoint;
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
                    ->map(fn (DailyTracker $tracker) => $this->scoreBreakdownFromDailyTracker($user, $tracker))
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
                    ->map(fn (UserPoint $point) => $this->scoreBreakdownFromUserPoint($point))
                    ->all(),
                $user
            );
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

        $trackerScores = $this->allTrackersByUserId(
            DailyTracker::query()
                ->whereIn('user_id', $userIds)
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
                ->whereIn('user_id', $userIds)
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

        $scores = [];
        foreach ($users as $user) {
            $userId = (string) $user->id;
            if (isset($trackerScores[$userId])) {
                $scores[$userId] = $this->summarizeBreakdowns(
                    $trackerScores[$userId]
                        ->map(fn (DailyTracker $tracker) => $this->scoreBreakdownFromDailyTracker($user, $tracker))
                        ->all(),
                    $user
                );
                continue;
            }

            if (isset($pointScores[$userId])) {
                $scores[$userId] = $this->summarizeBreakdowns(
                    $pointScores[$userId]
                        ->map(fn (UserPoint $point) => $this->scoreBreakdownFromUserPoint($point))
                        ->all(),
                    $user
                );
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

        // Use only the most recent day's breakdown. Averaging coreTaskScore
        // across every historical tracker row buried a user's actual current
        // standing under however many zero/partial days they had in the
        // past, making the leaderboard and dashboard score meaningless for
        // anyone with more than a few days of history.
        $latestBreakdown = $breakdowns[array_key_last($breakdowns)] ?? $breakdowns[0];
        $goalScore = (float) ($latestBreakdown['goalScore'] ?? 0);
        $coreTaskScore = (float) ($latestBreakdown['coreTaskScore'] ?? 0);
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
    private function scoreBreakdownFromDailyTracker(User $user, DailyTracker $tracker): array
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

        $goalScore = $tracker->todo_list_score > 0
            ? (float) $tracker->todo_list_score
            : (float) $tracker->todo_list_score_daily_contribution;
        $effectiveGoalScore = $goalScore > 0
            ? $goalScore
            : (float) $tracker->todo_list_score_daily_contribution;
        $includeTodoListScore = (bool) $tracker->todo_list_included_in_total
            || $goalScore > 0
            || $tracker->todo_list_score_daily_contribution > 0;

        $resolved = $includeTodoListScore
            ? (($dailyTrackerScore + $effectiveGoalScore) / 2)
            : $dailyTrackerScore;

        if ($resolved <= 0) {
            $resolved = (float) ($tracker->user_total_score ?? 0);
        }

        return [
            'goalScore' => $goalScore,
            'coreTaskScore' => $dailyTrackerScore,
            'overallScore' => $resolved,
        ];
    }

    /**
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    private function scoreBreakdownFromUserPoint(UserPoint $point): array
    {
        $dailyTrackerScore = (float) $point->daily_tracker_score;
        $goalScore = $point->todo_list_score > 0
            ? (float) $point->todo_list_score
            : (float) $point->todo_list_score_daily_contribution;
        $effectiveGoalScore = $goalScore > 0
            ? $goalScore
            : (float) $point->todo_list_score_daily_contribution;

        if ((bool) $point->todo_list_included_in_total
            || $goalScore > 0
            || $point->todo_list_score_daily_contribution > 0
        ) {
            $resolved = (($dailyTrackerScore + $effectiveGoalScore) / 2);
            if ($resolved > 0) {
                return [
                    'goalScore' => $goalScore,
                    'coreTaskScore' => $dailyTrackerScore,
                    'overallScore' => $resolved,
                ];
            }
        }

        if ($dailyTrackerScore > 0) {
            return [
                'goalScore' => $goalScore,
                'coreTaskScore' => $dailyTrackerScore,
                'overallScore' => $dailyTrackerScore,
            ];
        }

        $resolved = (float) ($point->user_total_score ?: $point->total_points);
        return [
            'goalScore' => $goalScore,
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
}
