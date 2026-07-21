<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\UserPoint;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Symfony\Component\HttpFoundation\Response;

class UserPointController extends Controller
{
    public function upsert(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'date' => ['required', 'date'],
            'username' => ['nullable', 'string', 'max:120'],
            'total_points' => ['nullable', 'numeric'],
            'activity_points' => ['nullable', 'integer', 'min:0'],
            'daily_tracker_score' => ['nullable', 'integer', 'min:0'],
            'todo_list_score' => ['nullable', 'integer', 'min:0'],
            'todo_list_score_daily_contribution' => ['nullable', 'integer', 'min:0'],
            'todo_list_included_in_total' => ['nullable', 'boolean'],
            'user_total_score' => ['nullable', 'integer', 'min:0'],
            'task_points' => ['nullable', 'array'],
            'tasks' => ['nullable', 'array'],
            'server' => ['nullable', 'string', 'max:120'],
            'company_id' => ['nullable', 'string', 'max:120'],
            'company_code' => ['nullable', 'string', 'max:120'],
            'company_name' => ['nullable', 'string', 'max:120'],
            'activity_counts' => ['nullable', 'array'],
        ]);

        $point = UserPoint::updateOrCreate(
            [
                'user_id' => $user->id,
                'date' => Carbon::parse($validated['date'])->toDateString(),
                'company_id' => $validated['company_id'] ?? $user->company_id,
            ],
            [
                'username' => $validated['username'] ?? $user->name,
                'total_points' => $validated['total_points'] ?? 0,
                'activity_points' => $validated['activity_points'] ?? 0,
                'daily_tracker_score' => $validated['daily_tracker_score'] ?? 0,
                'todo_list_score' => $validated['todo_list_score'] ?? 0,
                'todo_list_score_daily_contribution' => $validated['todo_list_score_daily_contribution'] ?? 0,
                'todo_list_included_in_total' => $validated['todo_list_included_in_total'] ?? false,
                'user_total_score' => $validated['user_total_score'] ?? 0,
                'task_points' => $validated['task_points'] ?? [],
                'tasks' => $validated['tasks'] ?? [],
                'server' => $validated['server'] ?? $user->company_name,
                'company_code' => $validated['company_code'] ?? $user->company_code,
                'company_name' => $validated['company_name'] ?? $user->company_name,
                'activity_counts' => $validated['activity_counts'] ?? [],
            ]
        );

        return response()->json([
            'point' => $this->pointPayload($point->refresh()),
        ]);
    }

    private function pointPayload(UserPoint $point): array
    {
        return [
            'id' => (string) $point->id,
            'userId' => (string) $point->user_id,
            'date' => $point->date?->toDateString(),
            'username' => $point->username,
            'totalPoints' => (float) $point->total_points,
            'activityPoints' => $point->activity_points,
            'dailyTrackerScore' => $point->daily_tracker_score,
            'todoListScore' => $point->todo_list_score,
            'todoListScoreDailyContribution' => $point->todo_list_score_daily_contribution,
            'todoListIncludedInTotal' => $point->todo_list_included_in_total,
            'userTotalScore' => $point->user_total_score,
            'taskPoints' => $point->task_points,
            'tasks' => $point->tasks,
            'server' => $point->server,
            'companyId' => $point->company_id,
            'companyCode' => $point->company_code,
            'companyName' => $point->company_name,
            'activityCounts' => $point->activity_counts,
        ];
    }
}
