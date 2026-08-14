<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DailyTracker;
use App\Models\ExerciseLog;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Database\QueryException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\Response;

class ExerciseController extends Controller
{
    /**
     * A stopped exercise session is an elapsed duration, not a calendar
     * interval. Keep the same 24-hour ceiling for both modern seconds-based
     * clients and legacy minutes-only clients so an old, restored session
     * cannot bypass the cap by omitting duration_seconds.
     */
    private const MAX_DURATION_SECONDS = 86_400;

    private const MAX_DURATION_MINUTES = self::MAX_DURATION_SECONDS / 60;

    /**
     * A small allowance handles devices whose clocks are slightly ahead while
     * still rejecting a queued payload that claims to end far in the future.
     */
    private const MAX_FUTURE_CLOCK_SKEW_SECONDS = 300;

    /**
     * A minutes-only client can only describe a whole minute. Permit a small
     * difference when timestamps are present, but keep the timestamps as the
     * authoritative elapsed duration.
     */
    private const MAX_DURATION_TIMESTAMP_DRIFT_SECONDS = 60;

    public function __construct(private readonly UserScoreService $userScoreService) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'date' => ['nullable', 'date'],
        ]);

        $query = ExerciseLog::query()
            ->where('user_id', $user->id)
            ->orderByDesc('created_at');

        if (isset($validated['date'])) {
            $query->whereDate('date', Carbon::parse($validated['date'])->toDateString());
        }

        $logs = $query
            ->get()
            ->map(fn (ExerciseLog $log) => $this->logPayload($log));

        return response()->json([
            'logs' => $logs,
        ]);
    }

    /**
     * Return just the logged sessions that have a photo, in small pages for
     * the personal exercise gallery. Keeping this separate from the daily
     * logger endpoint means opening the tracker never downloads a user's
     * entire photo history.
     */
    public function history(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'page' => ['nullable', 'integer', 'min:1'],
            'perPage' => ['nullable', 'integer', 'min:1'],
        ]);

        // A grid page contains at most two thumbnails per log. Bound it so a
        // long-running account cannot accidentally turn one scroll request
        // into a large media payload.
        $requestedPerPage = (int) ($validated['perPage'] ?? 18);
        $perPage = min(30, max(1, $requestedPerPage));
        $page = (int) ($validated['page'] ?? 1);

        $logs = ExerciseLog::query()
            ->where('user_id', $user->id)
            ->where(function ($photos): void {
                $photos
                    ->where(function ($startPhoto): void {
                        $startPhoto
                            ->whereNotNull('start_photo_url')
                            ->where('start_photo_url', '!=', '');
                    })
                    ->orWhere(function ($endPhoto): void {
                        $endPhoto
                            ->whereNotNull('end_photo_url')
                            ->where('end_photo_url', '!=', '');
                    });
            })
            ->orderByDesc('date')
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate($perPage, ['*'], 'page', $page);

        return response()->json([
            'logs' => $logs->getCollection()
                ->map(fn (ExerciseLog $log) => $this->logPayload($log))
                ->values(),
            'page' => (int) $logs->currentPage(),
            'perPage' => (int) $logs->perPage(),
            'hasMore' => $logs->hasMorePages(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'type' => ['required', 'string', 'max:120'],
            'duration_minutes' => ['nullable', 'integer', 'min:1', 'max:'.self::MAX_DURATION_MINUTES],
            'duration_seconds' => ['nullable', 'integer', 'min:1', 'max:'.self::MAX_DURATION_SECONDS],
            'intensity' => ['required', 'integer', 'min:1', 'max:3'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'start_photo_url' => ['nullable', 'string', 'max:2048'],
            'end_photo_url' => ['nullable', 'string', 'max:2048'],
            'date' => ['nullable', 'date'],
            // Clients generate this once when a session begins and retain it
            // in their offline queue. It is deliberately optional for older
            // installed builds that only know the legacy date/duration API.
            'client_session_id' => ['nullable', 'string', 'max:120', 'regex:/^[A-Za-z0-9][A-Za-z0-9_-]*$/'],
            'started_at' => ['nullable', 'date', 'required_with:ended_at'],
            'ended_at' => ['nullable', 'date', 'required_with:started_at'],
        ]);

        $clientSessionId = isset($validated['client_session_id'])
            ? trim($validated['client_session_id'])
            : null;

        // Return a prior successful write before calculating totals or
        // touching daily tracker/points data. This is the normal path when a
        // local-first client lost the first response and retries later.
        if ($clientSessionId !== null) {
            $existing = $this->findLogByClientSessionId($user, $clientSessionId);
            if ($existing !== null) {
                return $this->idempotentStoreResponse(
                    $this->attachMissingPhotoUrls($existing, $validated),
                );
            }
        }

        [$durationSeconds, $startedAt, $endedAt] = $this->resolveDurationAndTiming($validated);
        $durationMinutes = $this->durationMinutesFromSeconds($durationSeconds);
        $date = $this->resolveLogDate($validated, $startedAt, $endedAt);

        try {
            [$log, $created] = DB::transaction(function () use (
                $user,
                $validated,
                $clientSessionId,
                $durationMinutes,
                $durationSeconds,
                $startedAt,
                $endedAt,
                $date,
            ): array {
                // The first lookup above handles ordinary retries. This
                // locked lookup covers two simultaneous retries that both
                // reached the database before either created its row.
                if ($clientSessionId !== null) {
                    $existing = ExerciseLog::query()
                        ->where('user_id', $user->id)
                        ->where('client_session_id', $clientSessionId)
                        ->lockForUpdate()
                        ->first();

                    if ($existing !== null) {
                        return [
                            $this->attachMissingPhotoUrls($existing, $validated),
                            false,
                        ];
                    }
                }

                $log = ExerciseLog::create([
                    'id' => (string) Str::uuid(),
                    'user_id' => $user->id,
                    'client_session_id' => $clientSessionId,
                    'username' => $user->name,
                    'type' => trim($validated['type']),
                    'duration_minutes' => $durationMinutes,
                    'duration_seconds' => $durationSeconds,
                    'intensity' => $validated['intensity'],
                    'notes' => trim((string) ($validated['notes'] ?? '')),
                    'start_photo_url' => $validated['start_photo_url'] ?? null,
                    'end_photo_url' => $validated['end_photo_url'] ?? null,
                    'date' => $date,
                    'started_at' => $startedAt,
                    'ended_at' => $endedAt,
                ]);

                // Keep the log and derived activity data atomic. In
                // particular, a retry which loses its original response can
                // never apply these side effects for a second time.
                $this->syncDailyTracker($user, $date);
                $this->syncUserPoints($user, $date);

                return [$log, true];
            });
        } catch (QueryException $exception) {
            // A unique index is the final protection against a concurrent
            // insert. Once its winner commits, return that owned log rather
            // than applying tracker/points updates on the losing retry.
            if ($clientSessionId !== null && $this->isClientSessionUniqueViolation($exception)) {
                $existing = $this->findLogByClientSessionId($user, $clientSessionId);
                if ($existing !== null) {
                    return $this->idempotentStoreResponse(
                        $this->attachMissingPhotoUrls($existing, $validated),
                    );
                }
            }

            throw $exception;
        }

        if (! $created) {
            return $this->idempotentStoreResponse($log);
        }

        return $this->createdStoreResponse($log);
    }

    private function createdStoreResponse(ExerciseLog $log): JsonResponse
    {
        $date = $log->date?->toDateString() ?? now()->toDateString();

        return response()->json([
            'log' => $this->logPayload($log),
            'logs' => $this->logsForUser($log->user_id, $date),
            'alreadySynced' => false,
        ], Response::HTTP_CREATED);
    }

    private function idempotentStoreResponse(ExerciseLog $log): JsonResponse
    {
        $date = $log->date?->toDateString() ?? now()->toDateString();

        return response()->json([
            'log' => $this->logPayload($log),
            'logs' => $this->logsForUser($log->user_id, $date),
            'alreadySynced' => true,
        ]);
    }

    private function findLogByClientSessionId(User $user, string $clientSessionId): ?ExerciseLog
    {
        return ExerciseLog::query()
            ->where('user_id', $user->id)
            ->where('client_session_id', $clientSessionId)
            ->first();
    }

    /**
     * A record may have been saved before a delayed end-photo upload finished.
     * On a safe retry, fill empty photo slots on that same record but never
     * replace an already persisted photo URL with a later request's value.
     *
     * @param  array<string, mixed>  $validated
     */
    private function attachMissingPhotoUrls(ExerciseLog $log, array $validated): ExerciseLog
    {
        $changes = [];

        foreach (['start_photo_url', 'end_photo_url'] as $field) {
            $value = $validated[$field] ?? null;
            if (is_string($value) && trim($value) !== '' && blank($log->{$field})) {
                $changes[$field] = trim($value);
            }
        }

        if ($changes === []) {
            return $log;
        }

        $log->fill($changes)->save();

        return $log->refresh();
    }

    /**
     * @param  array<string, mixed>  $validated
     * @return array{0: int, 1: Carbon|null, 2: Carbon|null}
     */
    private function resolveDurationAndTiming(array $validated): array
    {
        $startedAt = isset($validated['started_at'])
            ? Carbon::parse($validated['started_at'])
            : null;
        $endedAt = isset($validated['ended_at'])
            ? Carbon::parse($validated['ended_at'])
            : null;

        if ($startedAt === null && $endedAt === null) {
            $durationSeconds = $this->durationSecondsFromPayload($validated);
            if ($durationSeconds < 1) {
                throw ValidationException::withMessages([
                    'duration_seconds' => [
                        'Provide duration_seconds, duration_minutes, or both started_at and ended_at.',
                    ],
                ]);
            }

            return [$durationSeconds, null, null];
        }

        if ($startedAt === null || $endedAt === null) {
            throw ValidationException::withMessages([
                'started_at' => ['started_at and ended_at must be provided together.'],
                'ended_at' => ['started_at and ended_at must be provided together.'],
            ]);
        }

        if (! $endedAt->greaterThan($startedAt)) {
            throw ValidationException::withMessages([
                'ended_at' => ['ended_at must be after started_at.'],
            ]);
        }

        $durationSeconds = (int) $startedAt->diffInSeconds($endedAt);
        if ($durationSeconds < 1) {
            throw ValidationException::withMessages([
                'ended_at' => ['The elapsed session duration must be between 1 second and 24 hours.'],
            ]);
        }

        if ($durationSeconds > self::MAX_DURATION_SECONDS) {
            // Forgotten exercise sessions can stay open for days on older
            // clients. Recover them by preserving the stop moment and local
            // calendar date while capping the elapsed duration to the same
            // 24-hour maximum enforced for modern local-first saves.
            $durationSeconds = self::MAX_DURATION_SECONDS;
            $startedAt = $endedAt->copy()->subSeconds($durationSeconds);
        }

        if ($endedAt->greaterThan(now()->addSeconds(self::MAX_FUTURE_CLOCK_SKEW_SECONDS))) {
            throw ValidationException::withMessages([
                'ended_at' => ['ended_at cannot be more than five minutes in the future.'],
            ]);
        }

        $reportedDurationSeconds = $this->durationSecondsFromPayload($validated);
        if (
            $reportedDurationSeconds > 0
            && abs($reportedDurationSeconds - $durationSeconds) > self::MAX_DURATION_TIMESTAMP_DRIFT_SECONDS
        ) {
            throw ValidationException::withMessages([
                'duration_seconds' => ['The supplied duration does not match started_at and ended_at.'],
            ]);
        }

        return [$durationSeconds, $startedAt, $endedAt];
    }

    /**
     * Timestamped sessions are attributed to their end date by default. A
     * supplied date can match either endpoint so a session crossing midnight
     * remains valid; old clients that send no timestamps retain date-only
     * behavior exactly as before.
     *
     * @param  array<string, mixed>  $validated
     */
    private function resolveLogDate(array $validated, ?Carbon $startedAt, ?Carbon $endedAt): string
    {
        $requestedDate = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : null;

        if ($startedAt === null || $endedAt === null) {
            return $requestedDate ?? now()->toDateString();
        }

        $startedDate = $startedAt->toDateString();
        $endedDate = $endedAt->toDateString();

        if (
            $requestedDate !== null
            && ! in_array($requestedDate, [$startedDate, $endedDate], true)
        ) {
            throw ValidationException::withMessages([
                'date' => ['The logged date must match started_at or ended_at.'],
            ]);
        }

        return $requestedDate ?? $endedDate;
    }

    private function isClientSessionUniqueViolation(QueryException $exception): bool
    {
        $sqlState = (string) $exception->getCode();
        $message = strtolower($exception->getMessage());

        return in_array($sqlState, ['23000', '23505'], true)
            || str_contains($message, 'exercise_logs_user_client_session_unique')
            || str_contains($message, 'unique constraint failed');
    }

    public function destroy(Request $request, string $logId): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $log = ExerciseLog::query()
            ->where('user_id', $user->id)
            ->where('id', $logId)
            ->first();

        if ($log === null) {
            return response()->json(['message' => 'Not found.'], Response::HTTP_NOT_FOUND);
        }

        $date = $log->date?->toDateString() ?? now()->toDateString();
        $log->delete();

        $this->syncDailyTracker($user, $date);
        $this->syncUserPoints($user, $date);

        return response()->json([
            'message' => 'Deleted.',
            'logs' => $this->logsForUser($user->id, $date),
        ]);
    }

    private function logsForUser(int|string $userId, string $date)
    {
        return ExerciseLog::query()
            ->where('user_id', $userId)
            ->whereDate('date', $date)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (ExerciseLog $log) => $this->logPayload($log));
    }

    private function syncDailyTracker(User $user, string $date): void
    {
        $logs = ExerciseLog::query()
            ->where('user_id', $user->id)
            ->whereDate('date', $date)
            ->get();

        $totalMinutes = $logs->sum(fn (ExerciseLog $log) => $this->logDurationMinutes($log));
        $existingTracker = DailyTracker::query()
            ->where('user_id', $user->id)
            ->whereDate('date', $date)
            ->first();

        $tracker = DailyTracker::updateOrCreate(
            [
                'user_id' => $user->id,
                'date' => $date,
            ],
            [
                'username' => $logs->first()?->username ?? $existingTracker?->username ?? 'User',
                'step_count' => $existingTracker?->step_count ?? 0,
                'step_goal' => $existingTracker?->step_goal ?? 5000,
                'meditation' => $existingTracker?->meditation ?? false,
                'steps' => $existingTracker?->steps ?? false,
                'call' => $existingTracker?->call ?? false,
                'learning' => $existingTracker?->learning ?? false,
                'add_value' => $existingTracker?->add_value ?? false,
                'todo_list' => $existingTracker?->todo_list ?? false,
                'exercise' => $logs->isNotEmpty(),
                'call_count' => $existingTracker?->call_count ?? 0,
                'exercise_count' => $logs->count(),
                'exercise_minutes' => $totalMinutes,
                'learning_count' => $existingTracker?->learning_count ?? 0,
                'value_count' => $existingTracker?->value_count ?? 0,
                'todo_list_count' => $existingTracker?->todo_list_count ?? 0,
                'todo_list_score' => $existingTracker?->todo_list_score ?? 0,
                'todo_list_score_daily_contribution' => $existingTracker?->todo_list_score_daily_contribution ?? 0,
                'todo_list_included_in_total' => $existingTracker?->todo_list_included_in_total ?? false,
                'user_total_score' => $existingTracker?->user_total_score ?? 0,
                'custom_daily_tasks' => $existingTracker?->custom_daily_tasks ?? [],
                'meditation_minutes' => $existingTracker?->meditation_minutes ?? 0,
                'company_id' => $user->company_id,
                'company_code' => $user->company_code,
                'company_name' => $user->company_name,
            ]
        );

        $this->userScoreService->recordFirstCompletedDailyTrackerAt($user, $tracker);
    }

    private function syncUserPoints(User $user, string $date): void
    {
        $logs = ExerciseLog::query()
            ->where('user_id', $user->id)
            ->whereDate('date', $date)
            ->get();

        $activityPoints = $logs->sum(fn (ExerciseLog $log) => max(1, $this->logDurationMinutes($log)));
        DB::table('user_points')->updateOrInsert(
            [
                'user_id' => $user->id,
                'date' => $date,
                'company_id' => $user->company_id,
            ],
            [
                'username' => $logs->first()?->username ?? 'User',
                'total_points' => $activityPoints,
                'activity_points' => $activityPoints,
                'daily_tracker_score' => min(100, $logs->count() * 10),
                'todo_list_score' => 0,
                'todo_list_score_daily_contribution' => 0,
                'todo_list_included_in_total' => false,
                'user_total_score' => min(100, $logs->count() * 10),
                'task_points' => json_encode(['Exercise Points' => $activityPoints]),
                'tasks' => json_encode(['Exercise' => $logs->isNotEmpty()]),
                'server' => $user->company_name ?? 'Default',
                'company_id' => $user->company_id,
                'company_code' => $user->company_code,
                'company_name' => $user->company_name,
                'activity_counts' => json_encode([
                    'exerciseCount' => $logs->count(),
                    'exerciseMinutes' => $logs->sum(fn (ExerciseLog $log) => $this->logDurationMinutes($log)),
                ]),
                'updated_at' => now(),
                'created_at' => now(),
            ]
        );

    }

    private function logPayload(ExerciseLog $log): array
    {
        $durationSeconds = $this->logDurationSeconds($log);

        return [
            'id' => $log->id,
            'userId' => (string) $log->user_id,
            'clientSessionId' => $log->client_session_id,
            'username' => $log->username,
            'type' => $log->type,
            // Keep the response internally consistent even for older rows
            // whose legacy minutes column does not match duration_seconds.
            'durationMinutes' => $this->durationMinutesFromSeconds($durationSeconds),
            'durationSeconds' => $durationSeconds,
            'intensity' => $log->intensity,
            'notes' => $log->notes,
            'startPhotoUrl' => $log->start_photo_url,
            'endPhotoUrl' => $log->end_photo_url,
            'date' => $log->date?->toDateString(),
            'startedAt' => $log->started_at?->toIso8601String(),
            'endedAt' => $log->ended_at?->toIso8601String(),
            'createdAt' => $log->created_at?->toIso8601String(),
        ];
    }

    private function logDurationSeconds(ExerciseLog $log): int
    {
        if ($log->duration_seconds !== null && $log->duration_seconds > 0) {
            return $log->duration_seconds;
        }

        return max(1, $log->duration_minutes * 60);
    }

    private function logDurationMinutes(ExerciseLog $log): int
    {
        return $this->durationMinutesFromSeconds($this->logDurationSeconds($log));
    }

    /**
     * Resolve the elapsed duration without adding legacy minutes to seconds.
     *
     * @param  array<string, mixed>  $validated
     */
    private function durationSecondsFromPayload(array $validated): int
    {
        $seconds = (int) ($validated['duration_seconds'] ?? 0);

        if ($seconds > 0) {
            return $seconds;
        }

        return (int) ($validated['duration_minutes'] ?? 0) * 60;
    }

    private function durationMinutesFromSeconds(int $durationSeconds): int
    {
        return max(1, (int) round($durationSeconds / 60));
    }
}
