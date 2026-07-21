<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\FastingHistory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Symfony\Component\HttpFoundation\Response;

class FastingController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        return response()->json([
            'session' => $this->sessionPayload($user),
            'history' => $this->historyQuery($user->id)->limit(6)->get()->map(
                fn (FastingHistory $history) => $this->historyPayload($history)
            ),
        ]);
    }

    public function history(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'limit' => ['nullable', 'integer', 'min:1', 'max:365'],
        ]);

        $limit = (int) ($validated['limit'] ?? 365);
        $history = $this->historyQuery($user->id)
            ->limit($limit)
            ->get()
            ->map(fn (FastingHistory $item) => $this->historyPayload($item));

        return response()->json(['history' => $history]);
    }

    public function start(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'target_hours' => ['required', 'integer', 'min:1', 'max:72'],
        ]);

        $now = now();
        $targetHours = (int) $validated['target_hours'];

        $user->forceFill([
            'fasting_target_hours' => $targetHours,
            'fasting_start_at' => $now,
            'fasting_end_at' => $now->copy()->addHours($targetHours),
        ])->save();

        return response()->json([
            'session' => $this->sessionPayload($user->refresh()),
        ]);
    }

    public function end(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $startedAt = $user->fasting_start_at instanceof Carbon
            ? $user->fasting_start_at
            : Carbon::parse($user->fasting_start_at);
        $plannedEnd = $user->fasting_end_at instanceof Carbon
            ? $user->fasting_end_at
            : Carbon::parse($user->fasting_end_at);

        if ($user->fasting_start_at === null) {
            return response()->json([
                'message' => 'No active fasting session.',
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $finishedAt = now();
        $completedHours = round($startedAt->diffInMinutes($finishedAt) / 60, 2);
        $completedTarget = $plannedEnd !== null && $finishedAt->greaterThanOrEqualTo($plannedEnd);

        $history = FastingHistory::create([
            'user_id' => $user->id,
            'target_hours' => (int) $user->fasting_target_hours,
            'start_time' => $startedAt,
            'planned_end_time' => $plannedEnd,
            'finished_at' => $finishedAt,
            'completed_hours' => $completedHours,
            'completed_target' => $completedTarget,
        ]);

        $user->forceFill([
            'fasting_target_hours' => $user->fasting_target_hours,
            'fasting_start_at' => null,
            'fasting_end_at' => null,
            'fasting_last_completed_at' => $finishedAt,
        ])->save();

        return response()->json([
            'session' => $this->sessionPayload($user->refresh()),
            'historyEntry' => $this->historyPayload($history),
        ]);
    }

    private function historyQuery(string $userId)
    {
        return FastingHistory::query()
            ->where('user_id', $userId)
            ->orderByDesc('finished_at');
    }

    private function sessionPayload($user): array
    {
        return [
            'targetHours' => $user->fasting_target_hours,
            'startTime' => $user->fasting_start_at?->toIso8601String(),
            'endTime' => $user->fasting_end_at?->toIso8601String(),
            'lastCompletedAt' => $user->fasting_last_completed_at?->toIso8601String(),
        ];
    }

    private function historyPayload(FastingHistory $history): array
    {
        return [
            'id' => (string) $history->id,
            'targetHours' => $history->target_hours,
            'startTime' => $history->start_time?->toIso8601String(),
            'plannedEndTime' => $history->planned_end_time?->toIso8601String(),
            'finishedAt' => $history->finished_at?->toIso8601String(),
            'completedHours' => (float) $history->completed_hours,
            'completedTarget' => $history->completed_target,
            'createdAt' => $history->created_at?->toIso8601String(),
        ];
    }
}
