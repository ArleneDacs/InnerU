<?php

namespace App\Services;

use App\Models\DailyTracker;
use App\Models\Notification;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Owns the durable, server-side step-goal streak and medal calculation.
 *
 * Step counts can arrive from the phone UI, Apple Health, Android's
 * background worker, the watch, or an offline queue.  Keeping the award
 * decision here means each of those paths uses the same source of truth:
 * DailyTracker rows whose recorded step count reached that day's goal.
 */
class StepGoalAchievementService
{
    // The largest defined medal is 100 days. We only need that many dates on
    // either side of a changed tracker to determine every newly-affected
    // medal, including an out-of-order offline sync that joins two runs.
    private const MAX_MILESTONE_DAYS = 100;

    /**
     * Keep these IDs aligned with the existing Flutter Step rewards screen.
     *
     * @var list<array{id:string,title:string,tier:string,days:int,description:string}>
     */
    private const MILESTONES = [
        [
            'id' => 'first_stride',
            'title' => 'First Stride',
            'tier' => 'Bronze',
            'days' => 3,
            'description' => 'Reached your step goal for 3 days in a row.',
        ],
        [
            'id' => 'steady_steps',
            'title' => 'Steady Steps',
            'tier' => 'Bronze',
            'days' => 7,
            'description' => 'Kept a 7-day step goal streak.',
        ],
        [
            'id' => 'walking_rhythm',
            'title' => 'Walking Rhythm',
            'tier' => 'Silver',
            'days' => 14,
            'description' => 'Hit your step goal for two full weeks.',
        ],
        [
            'id' => 'thirty_day_trail',
            'title' => 'Thirty Day Trail',
            'tier' => 'Silver',
            'days' => 30,
            'description' => 'Completed a full month of daily step goals.',
        ],
        [
            'id' => 'distance_builder',
            'title' => 'Distance Builder',
            'tier' => 'Gold',
            'days' => 60,
            'description' => 'Built a 60-day movement habit.',
        ],
        [
            'id' => 'unbroken_path',
            'title' => 'Unbroken Path',
            'tier' => 'Platinum',
            'days' => 100,
            'description' => 'Reached 100 days of daily step goals.',
        ],
    ];

    /**
     * Recomputes a user's Step achievements after one DailyTracker upsert.
     *
     * Locking the user serializes concurrent phone/background/watch writes,
     * so only the request that first adds a milestone can return it or create
     * its notification.
     *
     * @return array{
     *   goalMet: bool,
     *   currentStreak: int,
     *   longestStreak: int,
     *   lastCompletedDate: string|null,
     *   unlockedRewardIds: list<string>,
     *   newRewards: list<array{id:string,title:string,tier:string,days:int,description:string,unlockedAt:string}>
     * }
     */
    public function syncForDailyTracker(User $user, DailyTracker $tracker): array
    {
        return DB::transaction(function () use ($user, $tracker): array {
            /** @var User $lockedUser */
            $lockedUser = User::query()
                ->lockForUpdate()
                ->findOrFail($user->getKey());

            /** @var DailyTracker $freshTracker */
            $freshTracker = DailyTracker::query()
                ->whereKey($tracker->getKey())
                ->firstOrFail();

            return $this->syncLocked($lockedUser, $freshTracker);
        });
    }

    /**
     * Reconciles recently-recorded step-goal days that existed before this
     * server-side system was deployed. This is deliberately independent of a
     * new tracker write: a user can open the app on a rest day and still have
     * their prior qualifying streak reflected immediately.
     *
     * @return array{
     *   goalMet: bool,
     *   currentStreak: int,
     *   longestStreak: int,
     *   lastCompletedDate: string|null,
     *   unlockedRewardIds: list<string>,
     *   newRewards: list<array{id:string,title:string,tier:string,days:int,description:string,unlockedAt:string}>
     * }
     */
    public function reconcileForUser(User $user): array
    {
        return DB::transaction(function () use ($user): array {
            /** @var User $lockedUser */
            $lockedUser = User::query()
                ->lockForUpdate()
                ->findOrFail($user->getKey());

            return $this->syncLocked($lockedUser);
        });
    }

    /**
     * @return array{
     *   goalMet: bool,
     *   currentStreak: int,
     *   longestStreak: int,
     *   lastCompletedDate: string|null,
     *   unlockedRewardIds: list<string>,
     *   newRewards: list<array{id:string,title:string,tier:string,days:int,description:string,unlockedAt:string}>
     * }
     */
    private function syncLocked(User $user, ?DailyTracker $tracker = null): array
    {
        $storedRewards = is_array($user->steps_streak_rewards)
            ? $user->steps_streak_rewards
            : [];
        $rewards = $storedRewards;
        $newRewards = [];

        $goal = (int) ($tracker?->step_goal ?? 0);
        $stepCount = (int) ($tracker?->step_count ?? 0);
        $goalMet = $tracker !== null && $goal > 0 && $stepCount >= $goal;
        $trackerDate = $tracker === null
            ? null
            : Carbon::parse($tracker->date)->startOfDay();

        /** @var DailyTracker|null $latestCompletedTracker */
        $latestCompletedTracker = DailyTracker::query()
            ->where('user_id', $user->id)
            ->where('step_goal', '>', 0)
            ->whereColumn('step_count', '>=', 'step_goal')
            ->orderByDesc('date')
            ->first(['date']);

        // Existing users can have legacy client-computed state before any
        // DailyTracker rows reach their goal. Do not turn their visible
        // medals/streak into zeros merely because this server has no
        // authoritative completion yet.
        if ($latestCompletedTracker === null) {
            return [
                'goalMet' => $goalMet,
                'currentStreak' => max(0, (int) ($user->steps_streak_current ?? 0)),
                'longestStreak' => max(0, (int) ($user->steps_streak_longest ?? 0)),
                'lastCompletedDate' => $this->dateKeyOrNull($user->steps_streak_last_date),
                'unlockedRewardIds' => array_values(array_keys($rewards)),
                'newRewards' => [],
            ];
        }

        $latestCompletedDate = Carbon::parse($latestCompletedTracker->date)
            ->startOfDay();
        $currentWindow = $this->completedDateKeys(
            $user,
            $latestCompletedDate->copy()->subDays(self::MAX_MILESTONE_DAYS),
            $latestCompletedDate,
        );
        $observedCurrentStreak = $this->consecutiveRunLength(
            $latestCompletedDate,
            $currentWindow,
            backwards: true,
        );
        $currentStreak = $this->resolveCurrentStreak(
            $user,
            $latestCompletedDate,
            $observedCurrentStreak,
        );

        // Reconcile every recent qualifying run, not just the tracker that
        // happened to trigger this request. This backfills users whose step
        // data arrived before the achievement service, including a profile
        // fetch on a later rest day.
        $windowLongestStreak = 0;
        foreach ($this->runsInWindow($currentWindow) as $run) {
            $windowLongestStreak = max($windowLongestStreak, $run['length']);
            $newRewards = [
                ...$newRewards,
                ...$this->unlockRewardsForRun(
                    $run['start'],
                    $run['length'],
                    $rewards,
                ),
            ];
        }

        $affectedRunLength = 0;
        if ($goalMet && $trackerDate !== null) {
            $affectedWindow = $this->completedDateKeys(
                $user,
                $trackerDate->copy()->subDays(self::MAX_MILESTONE_DAYS - 1),
                $trackerDate->copy()->addDays(self::MAX_MILESTONE_DAYS - 1),
            );
            $affectedRun = $this->runContaining($trackerDate, $affectedWindow);
            $affectedRunLength = $affectedRun['length'];
            $newRewards = [
                ...$newRewards,
                ...$this->unlockRewardsForRun(
                    $affectedRun['start'],
                    $affectedRun['length'],
                    $rewards,
                ),
            ];
        }

        // Preserve an already-recorded best streak during the migration from
        // the legacy client-owned implementation. New awards are nevertheless
        // based only on server-recorded DailyTracker data above. The affected
        // run is bounded to the largest milestone because a longer run cannot
        // unlock a new, larger medal today.
        $longestStreak = max(
            $currentStreak,
            $windowLongestStreak,
            $affectedRunLength,
            max(0, (int) ($user->steps_streak_longest ?? 0)),
        );

        $user->forceFill([
            'steps_streak_current' => $currentStreak,
            'steps_streak_longest' => $longestStreak,
            'steps_streak_last_date' => $latestCompletedDate->toDateString(),
            'steps_streak_rewards' => $rewards,
        ]);
        // Profile loads invoke reconciliation for historical backfill. Avoid
        // an unnecessary users-table write on every subsequent /api/me once
        // the stored streak state already matches the tracker history.
        if ($user->isDirty()) {
            $user->save();
        }

        foreach ($newRewards as $reward) {
            Notification::createFor(
                (string) $user->id,
                'streak_milestone',
                sprintf('%d-day Steps streak!', $reward['days']),
                sprintf(
                    'You hit the "%s" milestone: %d days of Steps.',
                    $reward['title'],
                    $reward['days'],
                ),
                [
                    'milestone' => $reward['title'],
                    'days' => $reward['days'],
                    'activity' => 'Steps',
                    'activityType' => 'steps',
                    'achievementId' => $reward['id'],
                    'unlockedAt' => $reward['unlockedAt'],
                ],
            );
        }

        return [
            'goalMet' => $goalMet,
            'currentStreak' => $currentStreak,
            'longestStreak' => $longestStreak,
            'lastCompletedDate' => $latestCompletedDate->toDateString(),
            'unlockedRewardIds' => array_values(array_keys($rewards)),
            'newRewards' => $newRewards,
        ];
    }

    /**
     * @return array<string, true>
     */
    private function completedDateKeys(User $user, Carbon $from, Carbon $through): array
    {
        return DailyTracker::query()
            ->where('user_id', $user->id)
            ->where('step_goal', '>', 0)
            ->whereColumn('step_count', '>=', 'step_goal')
            ->whereBetween('date', [$from->toDateString(), $through->toDateString()])
            ->pluck('date')
            ->mapWithKeys(fn ($date) => [Carbon::parse($date)->toDateString() => true])
            ->all();
    }

    /**
     * @param  array<string, true>  $completedDateKeys
     */
    private function consecutiveRunLength(
        Carbon $date,
        array $completedDateKeys,
        bool $backwards,
    ): int {
        $length = 0;
        $cursor = $date->copy();

        while (isset($completedDateKeys[$cursor->toDateString()])) {
            $length++;
            $cursor = $backwards ? $cursor->subDay() : $cursor->addDay();
        }

        return $length;
    }

    /**
     * @param  array<string, true>  $completedDateKeys
     * @return array{start: Carbon, length: int}
     */
    private function runContaining(Carbon $date, array $completedDateKeys): array
    {
        $before = $this->consecutiveRunLength(
            $date->copy()->subDay(),
            $completedDateKeys,
            backwards: true,
        );
        $after = $this->consecutiveRunLength(
            $date,
            $completedDateKeys,
            backwards: false,
        );

        return [
            'start' => $date->copy()->subDays($before),
            'length' => $before + $after,
        ];
    }

    /**
     * @param  array<string, true>  $completedDateKeys
     * @return list<array{start: Carbon, length: int}>
     */
    private function runsInWindow(array $completedDateKeys): array
    {
        $dateKeys = array_keys($completedDateKeys);
        sort($dateKeys, SORT_STRING);

        $runs = [];
        $start = null;
        $previous = null;
        $length = 0;

        foreach ($dateKeys as $dateKey) {
            $date = Carbon::parse($dateKey)->startOfDay();
            if ($previous !== null && ! $previous->copy()->addDay()->isSameDay($date)) {
                $runs[] = ['start' => $start, 'length' => $length];
                $start = null;
                $length = 0;
            }

            if ($start === null) {
                $start = $date;
            }
            $length++;
            $previous = $date;
        }

        if ($start !== null) {
            $runs[] = ['start' => $start, 'length' => $length];
        }

        return $runs;
    }

    /**
     * @param  array<string, mixed>  $rewards
     * @return list<array{id:string,title:string,tier:string,days:int,description:string,unlockedAt:string}>
     */
    private function unlockRewardsForRun(
        Carbon $start,
        int $length,
        array &$rewards,
    ): array {
        $newRewards = [];

        foreach (self::MILESTONES as $milestone) {
            if ($length < $milestone['days']
                || array_key_exists($milestone['id'], $rewards)) {
                continue;
            }

            $unlockedAt = $start
                ->copy()
                ->addDays($milestone['days'] - 1)
                ->toDateString();
            $rewards[$milestone['id']] = $unlockedAt;
            $newRewards[] = [
                ...$milestone,
                'unlockedAt' => $unlockedAt,
            ];
        }

        return $newRewards;
    }

    private function resolveCurrentStreak(
        User $user,
        Carbon $latestCompletedDate,
        int $observedCurrentStreak,
    ): int {
        $storedCurrentStreak = max(0, (int) ($user->steps_streak_current ?? 0));
        $storedLastDate = $this->dateKeyOrNull($user->steps_streak_last_date);
        $latestDateKey = $latestCompletedDate->toDateString();

        if ($storedLastDate === $latestDateKey) {
            return max($storedCurrentStreak, $observedCurrentStreak);
        }

        if ($storedLastDate === $latestCompletedDate->copy()->subDay()->toDateString()) {
            return max($observedCurrentStreak, $storedCurrentStreak + 1);
        }

        return $observedCurrentStreak;
    }

    private function dateKeyOrNull(mixed $value): ?string
    {
        if ($value === null || trim((string) $value) === '') {
            return null;
        }

        try {
            return Carbon::parse($value)->toDateString();
        } catch (\Throwable) {
            return null;
        }
    }
}
