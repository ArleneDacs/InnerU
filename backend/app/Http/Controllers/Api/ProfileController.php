<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\StepGoalAchievementService;
use App\Services\UserScoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\Response;

class ProfileController extends Controller
{
    public function __construct(
        private readonly UserScoreService $userScoreService,
        private readonly StepGoalAchievementService $stepGoalAchievementService,
    ) {}

    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json([
                'message' => 'No authenticated user found.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        // A user can have tracker rows saved before the server-owned Step
        // achievement service was introduced. Reconcile them here because the
        // rewards UI is driven by this profile payload, not by raw trackers.
        // This is idempotent: already-unlocked medals and notifications are
        // never duplicated on later profile loads.
        try {
            $this->stepGoalAchievementService->reconcileForUser($user);
            $user->refresh();
        } catch (\Throwable $throwable) {
            // Do not turn a temporary reconciliation issue into a forced
            // logout or blank profile. The next profile load retries it.
            report($throwable);
        }

        return response()->json([
            'user' => $this->userPayload($user),
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
            'default_landing_screen' => ['sometimes', 'string', Rule::in([
                'dashboard',
                'meditation',
                'steps',
                'goals',
                'community',
            ])],
            'meditation_streak_current' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'meditation_streak_longest' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'meditation_streak_last_date' => ['sometimes', 'nullable', 'date'],
            'meditation_streak_rewards' => ['sometimes', 'nullable', 'array'],
            'exercise_streak_current' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'exercise_streak_longest' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'exercise_streak_last_date' => ['sometimes', 'nullable', 'date'],
            'exercise_streak_rewards' => ['sometimes', 'nullable', 'array'],
            'fasting_streak_current' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'fasting_streak_longest' => ['sometimes', 'nullable', 'integer', 'min:0'],
            'fasting_streak_last_date' => ['sometimes', 'nullable', 'date'],
            'fasting_streak_rewards' => ['sometimes', 'nullable', 'array'],
            'daily_tracker_items' => ['sometimes', 'nullable', 'array'],
            'profile_pic' => ['sometimes', 'nullable', 'string', 'max:255'],
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
            'kind' => ['nullable', 'string', Rule::in(['avatar', 'image', 'community', 'video', 'step_proof', 'group_photo', 'exercise'])],
            // Optional because current clients carry the key in the exercise
            // filename. New clients may send it explicitly without changing
            // the deterministic storage contract.
            'upload_key' => ['nullable', 'string', 'max:160'],
        ]);

        $file = $validated['file'];
        $kind = $validated['kind'] ?? 'image';
        $disk = $this->resolveUploadDisk($kind);
        $exerciseUpload = $kind === 'exercise'
            ? $this->exerciseUploadTarget($file, $user->id, $validated['upload_key'] ?? null)
            : null;

        [$path, $disk] = $this->storeUploadedMedia(
            $file,
            $user->id,
            $kind,
            $disk,
            $exerciseUpload['fileName'] ?? null,
            $exerciseUpload['directory'] ?? null,
        );

        if ($path === null) {
            return response()->json([
                'message' => 'Media upload failed. Please try again.',
            ], Response::HTTP_INTERNAL_SERVER_ERROR);
        }

        $url = Storage::disk($disk)->url($path);

        // Uploading media is storage-only. A profile picture changes only
        // through the explicit profile update endpoint.
        $payload = [
            'url' => $url,
            'profile_pic' => $url,
            'path' => $path,
            'user' => $this->userPayload($user->refresh()),
        ];

        if ($exerciseUpload !== null) {
            $payload['uploadKey'] = $exerciseUpload['uploadKey'];
            $payload['clientSessionId'] = $exerciseUpload['clientSessionId'];
            $payload['slot'] = $exerciseUpload['slot'];
        }

        return response()->json($payload);
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
            'score' => $this->userScoreService->resolveForUser($user),
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
            'defaultScreen' => $user->default_landing_screen ?? 'dashboard',
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

    /**
     * @return array{0: string|null, 1: string}
     */
    private function storeUploadedMedia(
        UploadedFile $file,
        int $userId,
        string $kind,
        string $preferredDisk,
        ?string $deterministicFileName = null,
        ?string $deterministicDirectory = null,
    ): array {
        $extension = $file->getClientOriginalExtension()
            ?: $file->extension()
            ?: 'jpg';

        $fileName = $deterministicFileName ?? $kind.'_'.now()->format('YmdHis').'.'.$extension;
        $directory = $deterministicDirectory ?? match ($kind) {
            'avatar' => "users/{$userId}/avatars",
            'community' => "users/{$userId}/community-images",
            'video' => "users/{$userId}/videos",
            'step_proof' => "users/{$userId}/step-proofs",
            'group_photo' => "users/{$userId}/group-photos",
            'exercise' => "users/{$userId}/exercise-sessions",
            default => "users/{$userId}/images",
        };
        $prefix = trim((string) config('filesystems.media_upload_path', ''), '/');
        if ($prefix !== '') {
            $directory = "{$prefix}/{$directory}";
        }
        $disks = array_values(array_unique(array_filter([
            $preferredDisk,
            'public',
        ])));

        foreach ($disks as $disk) {
            try {
                $path = "{$directory}/{$fileName}";

                // Reusing a deterministic exercise target avoids creating a
                // second media object when an offline queue retries the same
                // start/end upload after an uncertain network response.
                if ($deterministicFileName !== null && Storage::disk($disk)->exists($path)) {
                    return [$path, $disk];
                }

                $path = $file->storePubliclyAs($directory, $fileName, $disk);

                if (is_string($path) && $path !== '') {
                    return [$path, $disk];
                }
            } catch (\Throwable $throwable) {
                report($throwable);
            }
        }

        return [null, $preferredDisk];
    }

    /**
     * Resolve an authenticated exercise image to a stable, user-scoped path.
     * Existing Flutter builds already name files
     * "exercise_<client-session-id>_<start|end>.jpg". An explicit upload_key
     * is accepted as the same key for future callers, but never required.
     *
     * @return array{clientSessionId: string, slot: string, uploadKey: string, fileName: string, directory: string}
     */
    private function exerciseUploadTarget(UploadedFile $file, int $userId, ?string $uploadKey): array
    {
        $key = is_string($uploadKey) && trim($uploadKey) !== ''
            ? trim($uploadKey)
            : pathinfo(basename($file->getClientOriginalName()), PATHINFO_FILENAME);

        if (! preg_match('/\Aexercise_([A-Za-z0-9][A-Za-z0-9_-]{0,119})_(start|end)\z/iD', $key, $matches)) {
            throw ValidationException::withMessages([
                'file' => [
                    'Exercise uploads must use exercise_<client-session-id>_<start|end> as their filename or upload_key.',
                ],
            ]);
        }

        $extension = strtolower($file->getClientOriginalExtension() ?: $file->extension() ?: 'jpg');
        if (! preg_match('/\A[a-z0-9]{1,10}\z/D', $extension)) {
            throw ValidationException::withMessages([
                'file' => ['The exercise upload file extension is invalid.'],
            ]);
        }

        $clientSessionId = $matches[1];
        $slot = strtolower($matches[2]);

        return [
            'clientSessionId' => $clientSessionId,
            'slot' => $slot,
            'uploadKey' => "exercise_{$clientSessionId}_{$slot}",
            'fileName' => "{$slot}.{$extension}",
            'directory' => "users/{$userId}/exercise-sessions/{$clientSessionId}",
        ];
    }

    private function resolveUploadDisk(string $kind): string
    {
        $preferredDisk = config('filesystems.media_upload_disk', 'public');
        if ($kind !== 'community') {
            return $preferredDisk;
        }

        $s3Configured = filled(config('filesystems.disks.s3.bucket'))
            || filled(config('filesystems.disks.s3.url'))
            || filled(config('filesystems.disks.s3.endpoint'));
        if ($s3Configured) {
            return 's3';
        }

        $doConfigured = filled(config('filesystems.disks.do.bucket'))
            || filled(config('filesystems.disks.do.url'))
            || filled(config('filesystems.disks.do.endpoint'));
        if ($doConfigured) {
            return 'do';
        }

        return $preferredDisk;
    }
}
