<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DailyTracker;
use App\Models\ExerciseLog;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class ExerciseController extends Controller
{
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

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'type' => ['required', 'string', 'max:120'],
            'duration_minutes' => ['nullable', 'integer', 'min:1', 'max:10000', 'required_without:duration_seconds'],
            'duration_seconds' => ['nullable', 'integer', 'min:1', 'max:86400', 'required_without:duration_minutes'],
            'intensity' => ['required', 'integer', 'min:1', 'max:3'],
            'notes' => ['nullable', 'string', 'max:2000'],
            'start_photo_url' => ['nullable', 'string', 'max:2048'],
            'end_photo_url' => ['nullable', 'string', 'max:2048'],
            'date' => ['nullable', 'date'],
        ]);

        $durationSeconds = (int) ($validated['duration_seconds'] ?? 0);
        if ($durationSeconds <= 0) {
            $durationMinutes = (int) ($validated['duration_minutes'] ?? 0);
            $durationSeconds = $durationMinutes * 60;
        }

        $durationMinutes = max(1, (int) round($durationSeconds / 60));

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

        DailyTracker::updateOrCreate(
            [
                'user_id' => $user->id,
                'date' => $date,
            ],
            [
                'username' => $logs->first()?->username ?? 'User',
                'step_count' => 0,
                'step_goal' => 5000,
                'meditation' => false,
                'steps' => false,
                'learning' => false,
                'add_value' => false,
                'exercise' => $logs->isNotEmpty(),
                'exercise_count' => $logs->count(),
                'exercise_minutes' => $totalMinutes,
                'meditation_minutes' => 0,
                'company_id' => $user->company_id,
                'company_code' => $user->company_code,
                'company_name' => $user->company_name,
            ]
        );
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
        return [
            'id' => $log->id,
            'userId' => (string) $log->user_id,
            'username' => $log->username,
            'type' => $log->type,
            'durationMinutes' => $log->duration_minutes,
            'durationSeconds' => $this->logDurationSeconds($log),
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
        return max(1, (int) round($this->logDurationSeconds($log) / 60));
    }
}
