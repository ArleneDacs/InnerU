<?php

namespace App\Services;

use App\Models\Company;
use App\Models\DailyTracker;
use App\Models\Goal;
use App\Models\GoalTask;
use App\Models\TodoTask;
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
        $company = $this->resolveCompaniesForUsers(collect([$user]))[(string) $user->id] ?? null;
        $goalScore = $this->resolveGoalScoreForUser($user, $company);
        if ($this->hasConfiguredPeriod($company)) {
            // The Goals page itself still shows raw completion status, but
            // leaderboard scoring should spread that score across the
            // configured period so an early-completed goal does not show up
            // as a full 100 immediately.
            return $this->scoreBreakdownForPeriod(
                $user,
                $company->leaderboard_period_start,
                $company->leaderboard_period_end,
                $goalScore,
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
            // The leaderboard ranking score comes only from daily tracker
            // activity. With no DailyTracker/UserPoint rows at all there is
            // no tracker activity to score, so the ranking is legitimately
            // 0 even though a goalScore exists -- goalScore is still
            // returned for informational display.
            return [
                'goalScore' => $goalScore,
                'coreTaskScore' => 0.0,
                'overallScore' => 0.0,
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
     * @param  Company|null  $knownCompany  When the caller has already
     *   resolved which company these users belong to (e.g. a company-scoped
     *   leaderboard), pass it here so every user is scored against that
     *   company instead of each user's own company fields being
     *   independently re-derived via resolveCompaniesForUsers/matchCompany.
     *   Those two resolvers don't always agree -- matchCompany prioritizes
     *   active_company_id over company_id, so a user whose company_id
     *   matches the caller's already-resolved company but whose
     *   active_company_id has drifted elsewhere would otherwise silently
     *   skip that company's configured leaderboard period.
     * @return array<string, array{goalScore:float, coreTaskScore:float, overallScore:float}>
     */
    public function resolveBreakdownForUsers(Collection $users, ?Company $knownCompany = null): array
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

        $companiesByUser = $knownCompany !== null
            ? array_fill_keys($userIds, $knownCompany)
            : $this->resolveCompaniesForUsers($users);
        $goalScoresByUser = $this->resolveGoalScoresForUsers($users);

        $scores = [];
        $periodUserIds = [];

        foreach ($users as $user) {
            $userId = (string) $user->id;
            $company = $companiesByUser[$userId] ?? null;

            if ($this->hasConfiguredPeriod($company)) {
                $scores[$userId] = $this->scoreBreakdownForPeriod(
                    $user,
                    $company->leaderboard_period_start,
                    $company->leaderboard_period_end,
                    $goalScoresByUser[$userId] ?? null,
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
                // See the matching fallback in resolveBreakdownForUser(): no
                // tracker activity at all means the ranking score is 0,
                // even though goalScore is still available for display.
                $scores[$userId] = [
                    'goalScore' => $goalScore,
                    'coreTaskScore' => 0.0,
                    'overallScore' => 0.0,
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

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, string>
     */
    public function firstCompletedDailyTrackerAtForUsers(Collection $users, ?Company $knownCompany = null): array
    {
        $users = $users->values();
        if ($users->isEmpty()) {
            return [];
        }

        $userIds = $users
            ->pluck('id')
            ->map(static fn ($id) => (string) $id)
            ->filter()
            ->values()
            ->all();

        if ($userIds === []) {
            return [];
        }

        $today = Carbon::now()->startOfDay();

        if ($this->hasConfiguredPeriod($knownCompany)) {
            $start = $knownCompany->leaderboard_period_start->copy()->startOfDay();
            if ($today->lt($start)) {
                return [];
            }

            $end = $knownCompany->leaderboard_period_end->copy()->startOfDay();
            if ($today->gt($end)) {
                return [];
            }
        }

        $query = DailyTracker::query()
            ->whereIn('user_id', $userIds)
            ->whereDate('date', $today->toDateString())
            ->orderBy('updated_at')
            ->orderBy('created_at');

        $trackersByUser = $query->get()->groupBy(fn (DailyTracker $tracker) => (string) $tracker->user_id);
        $usersById = $users->keyBy(fn (User $user) => (string) $user->id);
        $firstCompletedAt = [];

        foreach ($trackersByUser as $userId => $trackers) {
            $user = $usersById->get((string) $userId);
            if ($user === null) {
                continue;
            }

            foreach ($trackers as $tracker) {
                $taskIds = $this->dailyTrackerIdsForTracker($user, $tracker);
                if ($taskIds === []) {
                    continue;
                }

                $isComplete = collect($taskIds)
                    ->every(fn (string $taskId): bool => $this->dailyTrackerTaskCompleted($tracker, $taskId));
                if (! $isComplete) {
                    continue;
                }

                $firstCompletedAt[(string) $userId] = optional($tracker->updated_at ?? $tracker->created_at)?->toIso8601String();
                break;
            }
        }

        return array_filter($firstCompletedAt);
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

        // Leaderboard ranking comes only from daily tracker activity.
        // goalScore is still averaged and returned above for informational
        // display, but it no longer feeds the ranking score.
        $overallScore = $coreTaskScore;

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
        $dailyTrackerScore = $this->scoreDailyTrackerTasks($user, $tracker);

        // goalScore is still resolved and returned below for informational
        // display, but the leaderboard ranking score (overallScore) is a
        // pure function of daily tracker activity only.
        $resolvedGoalScore = $goalScore ?? $this->legacyGoalScoreFromTracker($tracker);

        $resolved = $dailyTrackerScore;
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
        // goalScore is still resolved and returned below for informational
        // display, but the leaderboard ranking score (overallScore) is a
        // pure function of daily tracker activity only.
        $resolvedGoalScore = $goalScore ?? $this->legacyGoalScoreFromPoint($point);

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

    private function scoreDailyTrackerTasks(User $user, DailyTracker $tracker): float
    {
        $dailyTrackerIds = $this->dailyTrackerIdsForTracker($user, $tracker);
        $completedCount = 0;

        foreach ($dailyTrackerIds as $taskId) {
            if ($this->dailyTrackerTaskCompleted($tracker, $taskId)) {
                $completedCount++;
            }
        }

        return count($dailyTrackerIds) > 0
            ? (($completedCount / count($dailyTrackerIds)) * 100)
            : (float) ($tracker->user_total_score ?? 0);
    }

    /**
     * @return array<int, string>
     */
    private function dailyTrackerIdsForTracker(User $user, DailyTracker $tracker): array
    {
        $customDailyTasks = $tracker->custom_daily_tasks;
        if (is_array($customDailyTasks)) {
            $snapshotTaskIds = $customDailyTasks['__snapshotTaskIds'] ?? null;
            if (is_array($snapshotTaskIds)) {
                $ids = collect($snapshotTaskIds)
                    ->map(fn ($id) => trim((string) $id))
                    ->filter(fn (string $id) => $id !== '' && $id !== 'todoList')
                    ->unique()
                    ->values()
                    ->all();

                if ($ids !== []) {
                    return $ids;
                }
            }
        }

        return $this->dailyTrackerIdsForUser($user);
    }

    private function dailyTrackerTaskCompleted(DailyTracker $tracker, string $taskId): bool
    {
        $customDailyTasks = $tracker->custom_daily_tasks;
        if (is_array($customDailyTasks) && isset($customDailyTasks[$taskId])) {
            $customTask = $customDailyTasks[$taskId];
            if (is_array($customTask)) {
                if (($customTask['completed'] ?? false) === true) {
                    return true;
                }
            }

            if (is_bool($customTask)) {
                if ($customTask) {
                    return true;
                }
            }
        }

        $column = match ($taskId) {
            'call', 'steps', 'exercise', 'meditation', 'learning' => $taskId,
            'addValue' => 'add_value',
            default => null,
        };

        // Snapshot completion, the live checklist field, and recorded
        // activity evidence are additive. An automatic completion can update
        // the live field without rewriting the whole snapshot.
        if ($column !== null && (bool) $tracker->{$column}) {
            return true;
        }

        return match ($taskId) {
            'call' => (int) $tracker->call_count > 0,
            'steps' => (int) $tracker->step_count > 0,
            'exercise' => (int) $tracker->exercise_count > 0
                || (int) $tracker->exercise_minutes > 0,
            'meditation' => (int) $tracker->meditation_minutes > 0,
            'learning' => (int) $tracker->learning_count > 0,
            'addValue' => (int) $tracker->value_count > 0,
            default => false,
        };
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
        $today = Carbon::now()->startOfDay();
        $start = $start->copy()->startOfDay();

        // A period that hasn't started yet must score 0 even if a
        // DailyTracker row happens to exist dated on/after $start (e.g. a
        // device clock/timezone ahead of the server) -- the query below
        // only excludes rows outside [start, end], it doesn't know what
        // "today" actually is.
        if ($today->lt($start)) {
            return [
                'goalScore' => 0.0,
                'coreTaskScore' => 0.0,
                'overallScore' => 0.0,
            ];
        }

        // Never count rows dated beyond today, even within an active
        // period, for the same reason.
        $queryEnd = $end->copy()->startOfDay()->min($today);

        $trackers = DailyTracker::query()
            ->where('user_id', $user->id)
            ->whereBetween('date', [$start->toDateString(), $queryEnd->toDateString()])
            ->orderBy('date')
            ->get();

        $totalDays = $start->diffInDays($end) + 1;
        $normalizeLegacyGoalScore = $goalScore === null;

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
                $goalScoreValue = $normalizeLegacyGoalScore && $totalDays > 0
                    ? $this->roundOne(((float) $latestGoalScore) / $totalDays)
                    : (float) $latestGoalScore;

                // No daily tracker rows in the period at all -- the
                // leaderboard ranking score is 0 even though a goalScore
                // exists (goalScore is still returned for informational
                // display; it no longer feeds the ranking).
                return [
                    'goalScore' => $goalScoreValue,
                    'coreTaskScore' => 0.0,
                    'overallScore' => 0.0,
                ];
            }

            return [
                'goalScore' => 0.0,
                'coreTaskScore' => 0.0,
                'overallScore' => 0.0,
            ];
        }

        $coreTaskScore = $totalDays > 0 ? ($coreTaskScoreSum / $totalDays) : 0.0;
        $goalScoreValue = $latestGoalScore === null
            ? 0.0
            : ($normalizeLegacyGoalScore && $totalDays > 0
                ? $this->roundOne(((float) $latestGoalScore) / $totalDays)
                : (float) $latestGoalScore);

        // Leaderboard ranking comes only from daily tracker activity.
        // goalScoreValue is still computed and returned above for
        // informational display, but it no longer feeds the ranking score.
        $overallScore = $coreTaskScore;

        return [
            'goalScore' => $goalScoreValue,
            'coreTaskScore' => $coreTaskScore,
            'overallScore' => $overallScore,
        ];
    }

    private function resolveGoalScoreForUser(User $user, ?Company $knownCompany = null): ?float
    {
        return $this->resolveGoalScoresForUsers(collect([$user]), $knownCompany)[(string) $user->id] ?? null;
    }

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, float>
     */
    private function resolveGoalScoresForUsers(Collection $users, ?Company $knownCompany = null): array
    {
        $scores = $this->resolveGoalScoresFromGoalModel($users);
        $companiesByUser = $knownCompany !== null
            ? array_fill_keys(
                $users
                    ->pluck('id')
                    ->map(static fn ($id) => (string) $id)
                    ->filter()
                    ->values()
                    ->all(),
                $knownCompany,
            )
            : $this->resolveCompaniesForUsers($users);

        foreach ($scores as $userId => $score) {
            $company = $companiesByUser[$userId] ?? null;
            if (! $this->hasConfiguredPeriod($company)) {
                continue;
            }

            $periodDays = $company->leaderboard_period_start->copy()
                ->startOfDay()
                ->diffInDays($company->leaderboard_period_end->copy()->startOfDay()) + 1;

            $scores[$userId] = $periodDays > 0
                ? $this->roundOne(((float) $score) / $periodDays)
                : 0.0;
        }

        // The Goal/GoalTask models are a newer, structured goals system
        // that most users haven't adopted yet -- the "Goals" screen most
        // users actually see (todo_list.dart) is backed by TodoTask
        // instead. For any user with no Goal-model score, fall back to
        // scoring their TodoTask rows the exact same way that screen's own
        // "_todoScore" does, so the leaderboard matches what they see
        // there rather than silently reporting 0/legacy data.
        $usersWithoutGoalScore = $users->reject(
            fn (User $user) => array_key_exists((string) $user->id, $scores)
        );

        if ($usersWithoutGoalScore->isNotEmpty()) {
            $companiesByUser = $knownCompany !== null
                ? array_fill_keys(
                    $usersWithoutGoalScore
                        ->pluck('id')
                        ->map(static fn ($id) => (string) $id)
                        ->values()
                        ->all(),
                    $knownCompany,
                )
                : $this->resolveCompaniesForUsers($usersWithoutGoalScore);

            $usersByCompanyKey = [];
            foreach ($usersWithoutGoalScore as $user) {
                $userId = (string) $user->id;
                $company = $companiesByUser[$userId] ?? null;
                $companyKey = $company !== null ? 'company:' . (string) $company->id : 'user:' . $userId;

                $usersByCompanyKey[$companyKey] ??= [
                    'company' => $company,
                    'users' => collect(),
                ];
                $usersByCompanyKey[$companyKey]['users']->push($user);
            }

            foreach ($usersByCompanyKey as $group) {
                $company = $group['company'];
                $groupUsers = $group['users'];

                $todoTaskScores = $company !== null && $this->hasConfiguredPeriod($company)
                    ? $this->resolveGoalScoresFromTodoTasks(
                        $groupUsers,
                        $company->leaderboard_period_start,
                        $company->leaderboard_period_end,
                    )
                    : $this->resolveGoalScoresFromTodoTasks($groupUsers);

                $scores += $todoTaskScores;
            }
        }

        return $scores;
    }

    /**
     * @param  Collection<int, User>  $users
     * @return array<string, float>
     */
    private function resolveGoalScoresFromGoalModel(Collection $users): array
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
     * @param  Collection<int, User>  $users
     * @return array<string, float>
     */
    private function resolveGoalScoresFromTodoTasks(
        Collection $users,
        ?Carbon $periodStart = null,
        ?Carbon $periodEnd = null
    ): array
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

        $query = TodoTask::query()
            ->whereIn('user_id', $userIds)
            ->orderBy('user_id')
            ->orderBy('start_date')
            ->orderBy('created_at');

        if ($periodStart !== null && $periodEnd !== null) {
            $query->whereDate('start_date', '>=', $periodStart->toDateString())
                ->whereDate('start_date', '<=', $periodEnd->toDateString());
        }

        $tasks = $query->get([
            'user_id',
            'goal_type',
            'start_date',
            'due_date',
            'is_completed',
            'completed_at',
            'completion_dates',
            'sub_tasks',
        ]);

        if ($tasks->isEmpty()) {
            return [];
        }

        $tasksByUserId = $tasks->groupBy(fn (TodoTask $task) => (string) $task->user_id);
        $scores = [];

        foreach ($users as $user) {
            $userId = (string) $user->id;
            $userTasks = $tasksByUserId->get($userId, collect());
            if ($userTasks->isEmpty()) {
                continue;
            }

            $scores[$userId] = $periodStart !== null && $periodEnd !== null
                ? $this->scoreTodoTasksForPeriod($userTasks, $periodStart, $periodEnd)
                : $this->scoreTodoTasks($userTasks);
        }

        return $scores;
    }

    /**
     * @param  Collection<int, TodoTask>  $tasks
     */
    private function scoreTodoTasks(Collection $tasks): float
    {
        if ($tasks->isEmpty()) {
            return 0.0;
        }

        $totalProgress = $tasks->sum(fn (TodoTask $task) => $this->todoTaskProgress($task));

        return round($totalProgress / $tasks->count());
    }

    /**
     * @param  Collection<int, TodoTask>  $tasks
     */
    private function scoreTodoTasksForPeriod(Collection $tasks, Carbon $periodStart, Carbon $periodEnd): float
    {
        if ($tasks->isEmpty()) {
            return 0.0;
        }

        $periodStart = $periodStart->copy()->startOfDay();
        $periodEnd = $periodEnd->copy()->startOfDay();

        if ($periodEnd->lt($periodStart)) {
            return 0.0;
        }

        $totalPeriodDays = $periodStart->diffInDays($periodEnd) + 1;
        if ($totalPeriodDays <= 0) {
            return 0.0;
        }

        $totalProgress = $tasks->sum(
            fn (TodoTask $task) => $this->todoTaskPeriodProgress($task, $periodStart, $periodEnd, $totalPeriodDays)
        );

        return round($totalProgress / $tasks->count(), 2);
    }

    private function todoTaskPeriodProgress(
        TodoTask $task,
        Carbon $periodStart,
        Carbon $periodEnd,
        int $totalPeriodDays
    ): float {
        if ($totalPeriodDays <= 0) {
            return 0.0;
        }

        $today = Carbon::now()->startOfDay();
        if ($today->lt($periodStart)) {
            return 0.0;
        }

        $scoreEnd = $periodEnd->copy()->min($today);
        $earnedDayCredits = strtoupper((string) $task->goal_type) === 'EVERYDAY'
            ? $this->todoTaskEverydayEarnedDays($task, $periodStart, $scoreEnd)
            : $this->todoTaskOneTimeEarnedDays($task, $periodStart, $scoreEnd);

        return ($earnedDayCredits / $totalPeriodDays) * 100;
    }

    private function todoTaskOneTimeEarnedDays(TodoTask $task, Carbon $periodStart, Carbon $scoreEnd): float
    {
        $subTasks = is_array($task->sub_tasks) ? $task->sub_tasks : [];

        if ($subTasks !== []) {
            $completed = 0;
            foreach ($subTasks as $subTask) {
                if (is_array($subTask) && ($subTask['isCompleted'] ?? false) === true) {
                    $completed++;
                }
            }

            return count($subTasks) > 0 ? $completed / count($subTasks) : 0.0;
        }

        if (! $task->is_completed) {
            return 0.0;
        }

        $completedAt = $task->completed_at instanceof Carbon
            ? $task->completed_at->copy()
            : ($task->completed_at ? Carbon::parse($task->completed_at) : $this->todoTaskStartDate($task));
        if ($completedAt === null) {
            return 0.0;
        }
        $completedDate = $completedAt->startOfDay();

        $dueDate = $task->due_date instanceof Carbon
            ? $task->due_date->copy()
            : ($task->due_date ? Carbon::parse($task->due_date) : null);

        if ($dueDate !== null && $completedDate->gt($dueDate->startOfDay())) {
            return 0.0;
        }

        return $completedDate->betweenIncluded($periodStart, $scoreEnd) ? 1.0 : 0.0;
    }

    private function todoTaskEverydayEarnedDays(TodoTask $task, Carbon $periodStart, Carbon $scoreEnd): int
    {
        $taskStart = $this->todoTaskStartDate($task);
        $dueDate = $task->due_date instanceof Carbon
            ? $task->due_date->copy()
            : ($task->due_date ? Carbon::parse($task->due_date) : null);

        if ($taskStart === null || $dueDate === null) {
            return 0;
        }

        $rangeStart = $taskStart->startOfDay()->max($periodStart);
        $rangeEnd = $dueDate->startOfDay()->min($scoreEnd);

        if ($rangeEnd->lt($rangeStart)) {
            return 0;
        }

        $completedDates = collect($task->completion_dates ?? [])
            ->map(fn ($date) => Carbon::parse($date)->startOfDay())
            ->filter(fn (Carbon $date) => $date->betweenIncluded($rangeStart, $rangeEnd))
            ->map(fn (Carbon $date) => $date->toDateString())
            ->unique()
            ->values()
            ->all();

        if ($completedDates === [] && $task->is_completed) {
            $completedAt = $task->completed_at instanceof Carbon
                ? $task->completed_at->copy()
                : ($task->completed_at ? Carbon::parse($task->completed_at) : null);

            if ($completedAt !== null) {
                $completedDate = $completedAt->startOfDay();
                if ($completedDate->betweenIncluded($rangeStart, $rangeEnd)) {
                    $completedDates = [$completedDate->toDateString()];
                }
            }
        }

        return count($completedDates);
    }

    private function todoTaskStartDate(TodoTask $task): ?Carbon
    {
        return $task->start_date instanceof Carbon
            ? $task->start_date->copy()
            : ($task->start_date ? Carbon::parse($task->start_date) : null);
    }

    private function todoTaskProgress(TodoTask $task): float
    {
        if (strtoupper((string) $task->goal_type) === 'EVERYDAY') {
            return $this->todoTaskEverydayProgress($task);
        }

        $subTasks = is_array($task->sub_tasks) ? $task->sub_tasks : [];

        if ($subTasks !== []) {
            $completed = 0;
            foreach ($subTasks as $subTask) {
                if (is_array($subTask) && ($subTask['isCompleted'] ?? false) === true) {
                    $completed++;
                }
            }

            return ($completed / count($subTasks)) * 100;
        }

        if (! $task->is_completed) {
            return 0.0;
        }

        $completedAt = $task->completed_at instanceof Carbon
            ? $task->completed_at
            : ($task->completed_at ? Carbon::parse($task->completed_at) : null);
        $dueDate = $task->due_date instanceof Carbon
            ? $task->due_date
            : ($task->due_date ? Carbon::parse($task->due_date) : null);

        if ($completedAt !== null && $dueDate !== null && $completedAt->startOfDay()->gt($dueDate->startOfDay())) {
            return 0.0;
        }

        return 100.0;
    }

    private function todoTaskEverydayProgress(TodoTask $task): float
    {
        $startDate = $task->start_date instanceof Carbon
            ? $task->start_date
            : ($task->start_date ? Carbon::parse($task->start_date) : null);
        $dueDate = $task->due_date instanceof Carbon
            ? $task->due_date
            : ($task->due_date ? Carbon::parse($task->due_date) : null);

        if ($startDate === null || $dueDate === null) {
            return 0.0;
        }

        $rangeStart = $startDate->copy()->startOfDay();
        $rangeEnd = $dueDate->copy()->startOfDay();

        if ($rangeEnd->lt($rangeStart)) {
            return 0.0;
        }

        $eligibleDays = $rangeStart->diffInDays($rangeEnd) + 1;
        if ($eligibleDays <= 0) {
            return 0.0;
        }

        $completedDates = collect($task->completion_dates ?? [])
            ->map(fn ($date) => Carbon::parse($date)->startOfDay()->toDateString())
            ->unique()
            ->values()
            ->all();

        if ($completedDates === [] && $task->is_completed) {
            $completedAt = $task->completed_at instanceof Carbon
                ? $task->completed_at
                : ($task->completed_at ? Carbon::parse($task->completed_at) : null);

            if ($completedAt !== null) {
                $completedDates = [$completedAt->copy()->startOfDay()->toDateString()];
            }
        }

        $completedDays = collect($completedDates)
            ->map(fn ($date) => Carbon::parse($date)->startOfDay())
            ->filter(fn (Carbon $date) => $date->betweenIncluded($rangeStart, $rangeEnd))
            ->map(fn (Carbon $date) => $date->toDateString())
            ->unique()
            ->count();

        return ($completedDays / $eligibleDays) * 100;
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
