<?php

namespace App\Services;

use App\Models\DailyTracker;
use App\Models\User;
use App\Models\UserPoint;
use Illuminate\Support\Collection;

class UserScoreService
{
    public function resolveForUser(User $user): int
    {
        $latestScores = [];

        $latestPoint = UserPoint::query()
            ->where('user_id', $user->id)
            ->orderByDesc('updated_at')
            ->first(['user_total_score', 'updated_at']);
        if ($latestPoint !== null) {
            $latestScores[] = [
                'score' => $this->normalizeScore($latestPoint->user_total_score),
                'updated_at' => $latestPoint->updated_at?->getTimestamp() ?? 0,
            ];
        }

        $latestTracker = DailyTracker::query()
            ->where('user_id', $user->id)
            ->orderByDesc('updated_at')
            ->first(['user_total_score', 'updated_at']);
        if ($latestTracker !== null) {
            $latestScores[] = [
                'score' => $this->normalizeScore($latestTracker->user_total_score),
                'updated_at' => $latestTracker->updated_at?->getTimestamp() ?? 0,
            ];
        }

        if ($latestScores !== []) {
            usort(
                $latestScores,
                static fn (array $left, array $right): int => $right['updated_at'] <=> $left['updated_at']
            );

            return $latestScores[0]['score'];
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

        $pointScores = $this->latestScoresByUserId(
            UserPoint::query()
                ->whereIn('user_id', $userIds)
                ->orderBy('user_id')
                ->orderByDesc('updated_at')
                ->get(['user_id', 'user_total_score', 'updated_at'])
        );

        $trackerScores = $this->latestScoresByUserId(
            DailyTracker::query()
                ->whereIn('user_id', $userIds)
                ->orderBy('user_id')
                ->orderByDesc('updated_at')
                ->get(['user_id', 'user_total_score', 'updated_at'])
        );

        $scores = [];
        foreach ($users as $user) {
            $userId = (string) $user->id;
            $candidates = [];

            if (isset($pointScores[$userId])) {
                $candidates[] = $pointScores[$userId];
            }

            if (isset($trackerScores[$userId])) {
                $candidates[] = $trackerScores[$userId];
            }

            if ($candidates !== []) {
                usort(
                    $candidates,
                    static fn (array $left, array $right): int => $right['updated_at'] <=> $left['updated_at']
                );
                $scores[$userId] = $candidates[0]['score'];
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
        return $this->syncForUser($user, $this->extractScore($payload));
    }

    /**
     * @param  Collection<int, mixed>  $records
     * @return array<string, array{score:int, updated_at:int}>
     */
    private function latestScoresByUserId(Collection $records): array
    {
        $scores = [];

        foreach ($records as $record) {
            $userId = (string) $record->user_id;
            if (isset($scores[$userId])) {
                continue;
            }

            $scores[$userId] = [
                'score' => $this->normalizeScore($record->user_total_score),
                'updated_at' => $record->updated_at?->getTimestamp() ?? 0,
            ];
        }

        return $scores;
    }

    private function extractScore(array $payload): ?int
    {
        foreach (['user_total_score', 'total_points', 'score', 'daily_tracker_score'] as $key) {
            if (! array_key_exists($key, $payload)) {
                continue;
            }

            $value = $payload[$key];
            if ($value === null || $value === '' || is_bool($value)) {
                continue;
            }

            if (is_numeric($value)) {
                return $this->normalizeScore($value);
            }
        }

        return null;
    }

    private function normalizeScore(mixed $score): int
    {
        if ($score === null || $score === '' || is_bool($score)) {
            return 0;
        }

        return max(0, min(100, (int) round((float) $score)));
    }
}
