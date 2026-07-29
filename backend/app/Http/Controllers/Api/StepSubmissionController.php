<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CoachMentee;
use App\Models\DailyTracker;
use App\Models\Notification;
use App\Models\StepSubmission;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class StepSubmissionController extends Controller
{
    public function __construct(private readonly UserScoreService $userScoreService)
    {
    }

    /**
     * Mentee submits a manual step count with a photo proof for their
     * coach(es) to review. Always succeeds even if the mentee currently has
     * no assigned coach (there's just nobody to notify in that case).
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'steps' => ['required', 'integer', 'min:1'],
            'date' => ['required', 'date'],
            'proof_url' => ['required', 'string'],
            'note' => ['nullable', 'string', 'max:500'],
        ]);

        $date = Carbon::parse($validated['date'])->toDateString();

        $submission = StepSubmission::create([
            'id' => (string) Str::uuid(),
            'user_id' => (string) $user->id,
            'steps' => $validated['steps'],
            'date' => $date,
            'proof_url' => $validated['proof_url'],
            'note' => $validated['note'] ?? null,
            'status' => 'pending',
        ]);

        foreach (CoachMentee::coachIdsForMentee((string) $user->id) as $coachId) {
            Notification::createFor(
                $coachId,
                'step_submission_received',
                sprintf('%s submitted %d steps for approval', $user->name, $submission->steps),
                $submission->note,
                [
                    'submissionId' => (string) $submission->id,
                    'menteeId' => (string) $user->id,
                    'steps' => $submission->steps,
                    'date' => $date,
                ],
            );
        }

        return response()->json(['submission' => $this->payload($submission)], Response::HTTP_CREATED);
    }

    /**
     * The authenticated (mentee) user's own submission history, newest
     * first.
     */
    public function mine(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $submissions = StepSubmission::query()
            ->where('user_id', (string) $user->id)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (StepSubmission $submission) => $this->payload($submission));

        return response()->json(['submissions' => $submissions]);
    }

    /**
     * The authenticated coach's review queue: every submission from any of
     * their own mentees. Optional `?status=pending` filter. Unfiltered,
     * results are simply newest-first (created_at desc) — the client is
     * expected to tab/filter pending vs. reviewed itself, same as it does
     * for other list endpoints in this app.
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'status' => ['nullable', 'string', 'in:pending,approved,declined'],
        ]);

        $menteeIds = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->pluck('mentee_id')
            ->map(static fn ($id) => (string) $id)
            ->unique()
            ->values();

        if ($menteeIds->isEmpty()) {
            return response()->json(['submissions' => []]);
        }

        $query = StepSubmission::query()
            ->whereIn('user_id', $menteeIds->all());

        if (isset($validated['status'])) {
            $query->where('status', $validated['status']);
        }

        $submissions = $query
            ->orderByDesc('created_at')
            ->get();

        $menteesById = User::query()
            ->whereIn('id', $menteeIds->all())
            ->get()
            ->keyBy(fn (User $mentee) => (string) $mentee->id);

        $payload = $submissions->map(function (StepSubmission $submission) use ($menteesById) {
            $mentee = $menteesById->get((string) $submission->user_id);

            return $this->payload($submission, $mentee);
        });

        return response()->json(['submissions' => $payload]);
    }

    public function approve(Request $request, string $stepSubmission): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $submission = StepSubmission::find($stepSubmission);
        if ($submission === null) {
            return response()->json(['message' => 'Step submission not found.'], Response::HTTP_NOT_FOUND);
        }

        $isRelatedCoach = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->where('mentee_id', (string) $submission->user_id)
            ->exists();
        if (! $isRelatedCoach) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if ($submission->status !== 'pending') {
            return response()->json([
                'message' => 'This submission has already been reviewed.',
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $mentee = User::find($submission->user_id);

        DB::transaction(function () use ($submission, $user, $mentee): void {
            $submission->forceFill([
                'status' => 'approved',
                'reviewed_by' => (string) $user->id,
                'reviewed_at' => now(),
            ])->save();

            $date = $submission->date->toDateString();

            $existingTracker = DailyTracker::query()
                ->where('user_id', $submission->user_id)
                ->whereDate('date', $date)
                ->first();

            $tracker = DailyTracker::updateOrCreate(
                [
                    'user_id' => $submission->user_id,
                    'date' => $date,
                ],
                [
                    'username' => $existingTracker?->username ?? $mentee?->name ?? '',
                    'step_count' => max($existingTracker?->step_count ?? 0, $submission->steps),
                    'step_goal' => $existingTracker?->step_goal ?? 5000,
                    'meditation' => $existingTracker?->meditation ?? false,
                    'steps' => true,
                    'call' => $existingTracker?->call ?? false,
                    'exercise' => $existingTracker?->exercise ?? false,
                    'learning' => $existingTracker?->learning ?? false,
                    'add_value' => $existingTracker?->add_value ?? false,
                    'todo_list' => $existingTracker?->todo_list ?? false,
                    'call_count' => $existingTracker?->call_count ?? 0,
                    'exercise_count' => $existingTracker?->exercise_count ?? 0,
                    'exercise_minutes' => $existingTracker?->exercise_minutes ?? 0,
                    'learning_count' => $existingTracker?->learning_count ?? 0,
                    'value_count' => $existingTracker?->value_count ?? 0,
                    'todo_list_count' => $existingTracker?->todo_list_count ?? 0,
                    'todo_list_score' => $existingTracker?->todo_list_score ?? 0,
                    'todo_list_score_daily_contribution' => $existingTracker?->todo_list_score_daily_contribution ?? 0,
                    'todo_list_included_in_total' => $existingTracker?->todo_list_included_in_total ?? false,
                    'user_total_score' => $existingTracker?->user_total_score ?? 0,
                    'custom_daily_tasks' => $existingTracker?->custom_daily_tasks ?? [],
                    'meditation_minutes' => $existingTracker?->meditation_minutes ?? 0,
                    'company_id' => $existingTracker?->company_id ?? $mentee?->company_code,
                    'company_code' => $existingTracker?->company_code ?? $mentee?->company_code,
                    'company_name' => $existingTracker?->company_name ?? $mentee?->company_name,
                ]
            );

            if ($mentee !== null) {
                try {
                    $resolvedScore = $this->userScoreService->syncForUser($mentee);
                    $tracker->forceFill([
                        'user_total_score' => $resolvedScore,
                    ])->save();
                } catch (\Throwable $throwable) {
                    report($throwable);
                }
            }

            Notification::createFor(
                (string) $submission->user_id,
                'step_submission_approved',
                sprintf('Your %d-step submission was approved', $submission->steps),
                null,
                [
                    'submissionId' => (string) $submission->id,
                    'date' => $submission->date->toDateString(),
                ],
            );
        });

        return response()->json(['submission' => $this->payload($submission->fresh())]);
    }

    public function decline(Request $request, string $stepSubmission): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $submission = StepSubmission::find($stepSubmission);
        if ($submission === null) {
            return response()->json(['message' => 'Step submission not found.'], Response::HTTP_NOT_FOUND);
        }

        $isRelatedCoach = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->where('mentee_id', (string) $submission->user_id)
            ->exists();
        if (! $isRelatedCoach) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if ($submission->status !== 'pending') {
            return response()->json([
                'message' => 'This submission has already been reviewed.',
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $validated = $request->validate([
            'reason' => ['required', 'string', 'max:500'],
        ]);

        $submission->forceFill([
            'status' => 'declined',
            'decline_reason' => $validated['reason'],
            'reviewed_by' => (string) $user->id,
            'reviewed_at' => now(),
        ])->save();

        Notification::createFor(
            (string) $submission->user_id,
            'step_submission_declined',
            'Your step submission was declined',
            $validated['reason'],
            [
                'submissionId' => (string) $submission->id,
                'date' => $submission->date->toDateString(),
            ],
        );

        return response()->json(['submission' => $this->payload($submission->fresh())]);
    }

    private function payload(StepSubmission $submission, ?User $mentee = null): array
    {
        return [
            'id' => (string) $submission->id,
            'userId' => (string) $submission->user_id,
            'menteeName' => $mentee?->name,
            'steps' => (int) $submission->steps,
            'date' => $submission->date?->toDateString(),
            'proofUrl' => $submission->proof_url,
            'note' => $submission->note,
            'status' => $submission->status,
            'declineReason' => $submission->decline_reason,
            'reviewedBy' => $submission->reviewed_by,
            'reviewedAt' => $submission->reviewed_at?->toIso8601String(),
            'createdAt' => $submission->created_at?->toIso8601String(),
        ];
    }
}
