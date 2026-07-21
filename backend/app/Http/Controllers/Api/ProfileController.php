<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\Response;

class ProfileController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        return response()->json([
            'user' => $this->userPayload($request->user()),
        ]);
    }

    public function update(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json([
                'message' => 'No authenticated user found.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'name' => ['sometimes', 'string', 'max:120'],
            'email' => [
                'sometimes',
                'string',
                'email:rfc,dns',
                'max:255',
                Rule::unique('users', 'email')->ignore($user->id),
            ],
            'number' => ['sometimes', 'nullable', 'string', 'max:30'],
            'birthdate' => ['sometimes', 'nullable', 'date'],
            'has_company' => ['sometimes', 'boolean'],
            'company_id' => ['sometimes', 'nullable', 'string', 'max:255'],
            'active_company_id' => ['sometimes', 'nullable', 'string', 'max:255'],
            'active_company_code' => ['sometimes', 'nullable', 'string', 'max:255'],
            'active_company_name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'active_company_score_mode' => ['sometimes', 'nullable', 'string', 'max:80'],
            'score_mode' => ['sometimes', 'nullable', 'string', 'max:80'],
            'company_memberships' => ['sometimes', 'nullable', 'array'],
            'company_ids' => ['sometimes', 'nullable', 'array'],
            'company_codes' => ['sometimes', 'nullable', 'array'],
            'company_code' => ['sometimes', 'nullable', 'string', 'max:60'],
            'company_name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'daily_step_goal' => ['sometimes', 'nullable', 'integer', 'min:1', 'max:50000'],
            'meditation_streak_current' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'meditation_streak_longest' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'meditation_streak_last_date' => ['sometimes', 'nullable', 'date'],
            'meditation_streak_rewards' => ['sometimes', 'nullable', 'array'],
            'steps_streak_current' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'steps_streak_longest' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'steps_streak_last_date' => ['sometimes', 'nullable', 'date'],
            'steps_streak_rewards' => ['sometimes', 'nullable', 'array'],
            'exercise_streak_current' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'exercise_streak_longest' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'exercise_streak_last_date' => ['sometimes', 'nullable', 'date'],
            'exercise_streak_rewards' => ['sometimes', 'nullable', 'array'],
            'fasting_streak_current' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'fasting_streak_longest' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'fasting_streak_last_date' => ['sometimes', 'nullable', 'date'],
            'fasting_streak_rewards' => ['sometimes', 'nullable', 'array'],
            'daily_tracker_items' => ['sometimes', 'nullable', 'array'],
        ]);

        $user->fill($validated);
        $user->save();

        return response()->json([
            'user' => $this->userPayload($user->refresh()),
        ]);
    }

    public function uploadMedia(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json([
                'message' => 'No authenticated user found.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'file' => ['required', 'file', 'max:20480'],
            'kind' => ['nullable', 'string', Rule::in(['avatar', 'image', 'video'])],
        ]);

        $file = $validated['file'];
        $kind = $validated['kind'] ?? 'image';
        $extension = $file->getClientOriginalExtension() ?: $file->extension() ?: 'jpg';
        $path = $file->storePubliclyAs(
            "users/{$user->id}/{$kind}s",
            $kind.'_'.now()->format('YmdHis').'.'.$extension,
            's3'
        );

        $user->profile_pic = Storage::disk('s3')->url($path);
        $user->save();

        return response()->json([
            'url' => $user->profile_pic,
            'profile_pic' => $user->profile_pic,
            'path' => $path,
            'user' => $this->userPayload($user->refresh()),
        ]);
    }

    private function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'number' => $user->number,
            'role' => $user->role,
            'is_coach' => (bool) $user->is_coach,
            'company_code' => $user->company_code,
            'company_name' => $user->company_name,
            'companyId' => $user->company_id,
            'companyCode' => $user->company_code,
            'companyName' => $user->company_name,
            'hasCompany' => (bool) $user->has_company,
            'activeCompanyId' => $user->active_company_id,
            'activeCompanyCode' => $user->active_company_code,
            'activeCompanyName' => $user->active_company_name,
            'activeCompanyScoreMode' => $user->active_company_score_mode,
            'scoreMode' => $user->score_mode,
            'companyMemberships' => $user->company_memberships ?? [],
            'companyIds' => $user->company_ids ?? [],
            'companyCodes' => $user->company_codes ?? [],
            'dailyStepGoal' => $user->daily_step_goal,
            'meditationStreakCurrent' => $user->meditation_streak_current,
            'meditationStreakLongest' => $user->meditation_streak_longest,
            'meditationStreakLastDate' => $user->meditation_streak_last_date,
            'meditationStreakRewards' => $user->meditation_streak_rewards ?? [],
            'stepsStreakCurrent' => $user->steps_streak_current,
            'stepsStreakLongest' => $user->steps_streak_longest,
            'stepsStreakLastDate' => $user->steps_streak_last_date,
            'stepsStreakRewards' => $user->steps_streak_rewards ?? [],
            'exerciseStreakCurrent' => $user->exercise_streak_current,
            'exerciseStreakLongest' => $user->exercise_streak_longest,
            'exerciseStreakLastDate' => $user->exercise_streak_last_date,
            'exerciseStreakRewards' => $user->exercise_streak_rewards ?? [],
            'fastingStreakCurrent' => $user->fasting_streak_current,
            'fastingStreakLongest' => $user->fasting_streak_longest,
            'fastingStreakLastDate' => $user->fasting_streak_last_date,
            'fastingStreakRewards' => $user->fasting_streak_rewards ?? [],
            'dailyTrackerItems' => $user->daily_tracker_items ?? [],
            'birthdate' => optional($user->birthdate)?->format('Y-m-d'),
            'profile_pic' => $user->profile_pic,
            'created_at' => optional($user->created_at)?->toIso8601String(),
            'updated_at' => optional($user->updated_at)?->toIso8601String(),
        ];
    }
}
