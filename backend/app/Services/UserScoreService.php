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

    public function resolveForUser(User $user): int
    {
        $latestTracker = DailyTracker::query()
            ->where('user_id', $user->id)
            ->orderByDesc('updated_at')
            ->first([
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
        if ($latestTracker !== null) {
            return $this->scoreFromDailyTracker($user, $latestTracker);
        }

        $latestPoint = UserPoint::query()
            ->where('user_id', $user->id)
            ->orderByDesc('updated_at')
            ->first([
                'total_points',
                'activity_points',
                'daily_tracker_score',
                'todo_list_score',
                'todo_list_score_daily_contribution',
                'todo_list_included_in_total',
                'user_total_score',
                'updated_at',
            ]);
        if ($latestPoint !== null) {
            return $this->scoreFromUserPoint($latestPoint);
        }

        return $this->normalizeScore($user->score);
    }

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, int>
     */
    public function resolveForUsers(Collection $users): array
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

        $trackerScores = $this->latestTrackersByUserId(
            DailyTracker::query()
                ->whereIn('user_id', $userIds)
                ->orderBy('user_id')
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

        $pointScores = $this->latestPointsByUserId(
            UserPoint::query()
                ->whereIn('user_id', $userIds)
                ->orderBy('user_id')
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
                $scores[$userId] = $this->scoreFromDailyTracker($user, $trackerScores[$userId]);
                continue;
            }

            if (isset($pointScores[$userId])) {
                $scores[$userId] = $this->scoreFromUserPoint($pointScores[$userId]);
                continue;
            }

            $scores[$userId] = $this->normalizeScore($user->score);
        }

        return $scores;
    }

    public function syncForUser(User $user, ?int $score = null): int
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
     * @return array<string, array{score:int, updated_at:int}>
     */
    private function latestTrackersByUserId(Collection $records): array
    {
        $scores = [];

        foreach ($records as $record) {
            $userId = (string) $record->user_id;
            if (isset($scores[$userId])) {
                continue;
            }

            $scores[$userId] = $record;
        }

        return $scores;
    }

    /**
     * @param  Collection<int, UserPoint>  $records
     * @return array<string, UserPoint>
     */
    private function latestPointsByUserId(Collection $records): array
    {
        $scores = [];

        foreach ($records as $record) {
            $userId = (string) $record->user_id;
            if (isset($scores[$userId])) {
                continue;
            }

            $scores[$userId] = $record;
        }

        return $scores;
    }

    private function normalizeScore(mixed $score): int
    {
        if ($score === null || $score === '' || is_bool($score)) {
            return 0;
        }

        return max(0, min(100, (int) round((float) $score)));
    }

    private function scoreFromDailyTracker(User $user, DailyTracker $tracker): int
    {
        $dailyTrackerIds = $this->dailyTrackerIdsForUser($user);
        $completedCount = 0;

        foreach ($dailyTrackerIds as $taskId) {
            if ($this->dailyTrackerTaskCompleted($tracker, $taskId)) {
                $completedCount++;
            }
        }

        $dailyTrackerScore = count($dailyTrackerIds) > 0
            ? $this->normalizeScore(($completedCount / count($dailyTrackerIds)) * 100)
            : $this->normalizeScore($tracker->user_total_score);

        $todoListScoreContribution = $this->normalizeScore(
            $tracker->todo_list_score_daily_contribution > 0
                ? $tracker->todo_list_score_daily_contribution
                : $tracker->todo_list_score
        );
        $includeTodoListScore = (bool) $tracker->todo_list_included_in_total;

        $resolved = $includeTodoListScore
            ? (($dailyTrackerScore + $todoListScoreContribution) / 2)
            : $dailyTrackerScore;

        if ($resolved <= 0) {
            $resolved = $this->normalizeScore($tracker->user_total_score);
        }

        return $this->normalizeScore($resolved);
    }

    private function scoreFromUserPoint(UserPoint $point): int
    {
        $dailyTrackerScore = $this->normalizeScore($point->daily_tracker_score);
        $todoListScoreContribution = $this->normalizeScore(
            $point->todo_list_score_daily_contribution > 0
                ? $point->todo_list_score_daily_contribution
                : $point->todo_list_score
        );

        if ((bool) $point->todo_list_included_in_total) {
            $resolved = (($dailyTrackerScore + $todoListScoreContribution) / 2);
            if ($resolved > 0) {
                return $this->normalizeScore($resolved);
            }
        }

        if ($dailyTrackerScore > 0) {
            return $dailyTrackerScore;
        }

        return $this->normalizeScore($point->user_total_score ?: $point->total_points);
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
