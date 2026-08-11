<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DailyTracker;
use App\Models\ExerciseLog;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
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
            'duration_minutes' => ['nullable', 'integer', 'min:1', 'max:'.self::MAX_DURATION_MINUTES, 'required_without:duration_seconds'],
            'duration_seconds' => ['nullable', 'integer', 'min:1', 'max:'.self::MAX_DURATION_SECONDS, 'required_without:duration_minutes'],
            'intensity' => ['required', 'integer', 'min:1', 'max:3'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'start_photo_url' => ['nullable', 'string', 'max:2048'],
            'end_photo_url' => ['nullable', 'string', 'max:2048'],
            'date' => ['nullable', 'date'],
        ]);

        // duration_seconds is the canonical total. duration_minutes exists
        // for older app builds only and is derived when seconds are absent.
        // Never combine the two values: they describe the same duration.
        $durationSeconds = $this->durationSecondsFromPayload($validated);
        $durationMinutes = $this->durationMinutesFromSeconds($durationSeconds);

        $date = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : now()->toDateString();

        $log = ExerciseLog::create([
            'id' => (string) Str::uuid(),
            'user_id' => $user->id,
            'username' => $user->name,
            'type' => trim($validated['type']),
            'duration_minutes' => $durationMinutes,
            'duration_seconds' => $durationSeconds,
            'intensity' => $validated['intensity'],
            'notes' => trim((string) ($validated['notes'] ?? '')),
            'start_photo_url' => $validated['start_photo_url'] ?? null,
            'end_photo_url' => $validated['end_photo_url'] ?? null,
            'date' => $date,
        ]);

        $this->syncDailyTracker($user, $date);
        $this->syncUserPoints($user, $date);

        return response()->json([
            'log' => $this->logPayload($log),
            'logs' => $this->logsForUser($user->id, $date),
        ], Response::HTTP_CREATED);
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
