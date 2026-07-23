<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DailyTracker;
use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\CoachRequest;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class CoachManagementController extends Controller
{
    public function directory(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $isAdmin = $this->isAdmin($user);
        $companyId = $this->activeCompanyValue($user->active_company_id, $user->company_id);
        $companyCode = $this->activeCompanyValue($user->active_company_code, $user->company_code);
        $companyName = $this->activeCompanyValue($user->active_company_name, $user->company_name);

        $query = User::query()
            ->where(function ($builder): void {
                $builder->where('role', 'coach')
                    ->orWhere('is_coach', true);
            });

        if (! $isAdmin) {
            $query->where(function ($builder) use ($companyId, $companyCode, $companyName): void {
                if ($companyId !== '') {
                    $builder->where('company_id', $companyId)
                        ->orWhere('active_company_id', $companyId);
                }
                if ($companyCode !== '') {
                    $builder->orWhere('company_code', $companyCode)
                        ->orWhere('active_company_code', $companyCode);
                }
                if ($companyName !== '') {
                    $builder->orWhere('company_name', $companyName)
                        ->orWhere('active_company_name', $companyName);
                }
            });
        }

        $coaches = $query
            ->orderBy('name')
            ->get()
            ->map(fn (User $coach) => [
                'id' => (string) $coach->id,
                'name' => $coach->name,
                'email' => $coach->email,
                'number' => $coach->number,
                'role' => $coach->role,
                'isCoach' => (bool) $coach->is_coach,
                'isAdmin' => (bool) $coach->is_admin,
                'companyName' => $coach->company_name,
                'companyCode' => $coach->company_code,
                'profilePic' => $coach->profile_pic,
            ]);

        return response()->json([
            'coaches' => $coaches,
        ]);
    }

    public function users(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if (! $this->isCoach($user) && ! $this->isAdmin($user)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $companyId = $this->activeCompanyValue($user->active_company_id, $user->company_id);
        $companyCode = $this->activeCompanyValue($user->active_company_code, $user->company_code);
        $companyName = $this->activeCompanyValue($user->active_company_name, $user->company_name);

        $users = User::query()
            ->where('id', '!=', (string) $user->id)
            ->where(function ($builder) use ($companyId, $companyCode, $companyName): void {
                if ($companyId !== '') {
                    $builder->where('company_id', $companyId)
                        ->orWhere('active_company_id', $companyId);
                }
                if ($companyCode !== '') {
                    $builder->orWhere('company_code', $companyCode)
                        ->orWhere('active_company_code', $companyCode);
                }
                if ($companyName !== '') {
                    $builder->orWhere('company_name', $companyName)
                        ->orWhere('active_company_name', $companyName);
                }
            })
            ->orderBy('name')
            ->get()
            ->map(function (User $candidate) use ($user): array {
                $coachIds = CoachMentee::query()
                    ->where('mentee_id', (string) $candidate->id)
                    ->pluck('coach_id')
                    ->map(static fn ($coachId) => (string) $coachId)
                    ->filter()
                    ->unique()
                    ->values()
                    ->all();

                $relation = CoachMentee::query()
                    ->where('coach_id', (string) $user->id)
                    ->where('mentee_id', (string) $candidate->id)
                    ->first();

                return [
                    'id' => (string) $candidate->id,
                    'name' => $candidate->name,
                    'email' => $candidate->email,
                    'number' => $candidate->number,
                    'role' => $candidate->role,
                    'isCoach' => (bool) $candidate->is_coach,
                    'isAdmin' => (bool) $candidate->is_admin,
                    'companyName' => $candidate->company_name,
                    'companyCode' => $candidate->company_code,
                    'profilePic' => $candidate->profile_pic,
                    'coachIds' => $coachIds,
                    'assignedToMe' => $relation !== null,
                    'groupId' => $relation?->group_id,
                    'groupName' => $relation?->group_name,
                    'teamName' => $relation?->team_name,
                    'score' => (int) $candidate->score,
                    'createdAt' => $candidate->created_at?->toIso8601String(),
                    'updatedAt' => $candidate->updated_at?->toIso8601String(),
                ];
            })
            ->values();

        return response()->json([
            'users' => $users,
        ]);
    }

    public function groups(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $groups = CoachGroup::query()
            ->where(function ($builder) use ($user): void {
                $builder->where('coach_id', (string) $user->id)
                    ->orWhereJsonContains('coach_ids', (string) $user->id);
            })
            ->orderBy('name')
            ->get()
            ->map(fn (CoachGroup $group) => $this->groupPayload($group));

        return response()->json(['groups' => $groups]);
    }

    public function storeGroup(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
        ]);

        $group = CoachGroup::create([
            'id' => (string) Str::uuid(),
            'coach_id' => (string) $user->id,
            'coach_ids' => [(string) $user->id],
            'name' => trim($validated['name']),
            'member_ids' => [],
            'member_count' => 0,
            'company_code' => $user->company_code,
            'company_name' => $user->company_name,
        ]);

        return response()->json([
            'group' => $this->groupPayload($group),
        ], Response::HTTP_CREATED);
    }

    public function updateGroupCoaches(Request $request, CoachGroup $group): JsonResponse
    {
        $user = $request->user();
        if ($user === null || ! $this->userCanManageGroup($user, $group)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'coach_ids' => ['required', 'array', 'min:1', 'max:2'],
            'coach_ids.*' => ['string', 'max:255'],
        ]);

        $coachIds = collect($validated['coach_ids'])
            ->map(static fn ($coachId) => trim((string) $coachId))
            ->filter()
            ->unique()
            ->values()
            ->all();

        $coachIds = array_values(array_unique(array_filter([
            (string) $group->coach_id,
            ...$coachIds,
        ])));

        if (count($coachIds) > 2) {
            return response()->json([
                'message' => 'A group can only have up to 2 coaches.',
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        $group->coach_ids = $coachIds;
        $group->save();

        return response()->json([
            'group' => $this->groupPayload($group->fresh()),
        ]);
    }

    public function destroyGroup(Request $request, CoachGroup $group): JsonResponse
    {
        $user = $request->user();
        if ($user === null || ! $this->userCanManageGroup($user, $group)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        DB::transaction(function () use ($group): void {
            $coachIds = $this->groupCoachIds($group);

            CoachMentee::query()
                ->whereIn('coach_id', $coachIds)
                ->where('group_id', $group->id)
                ->update([
                    'group_id' => null,
                    'group_name' => null,
                    'updated_at' => now(),
                ]);

            $group->delete();
        });

        return response()->json(['message' => 'Deleted.']);
    }

    public function mentees(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $mentees = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->orderByDesc('updated_at')
            ->get()
            ->map(fn (CoachMentee $relation) => $this->menteePayload($relation));

        return response()->json(['mentees' => $mentees]);
    }

    public function assignMentee(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'mentee_id' => ['required', 'string', 'max:255'],
            'mentee_name' => ['nullable', 'string', 'max:255'],
            'mentee_email' => ['nullable', 'email', 'max:255'],
            'team_name' => ['required', 'string', 'max:255'],
            'group_id' => ['nullable', 'string', 'exists:coach_groups,id'],
            'group_name' => ['nullable', 'string', 'max:255'],
        ]);

        $groupId = trim((string) ($validated['group_id'] ?? ''));
        $groupName = trim((string) ($validated['group_name'] ?? ''));
        if ($groupId !== '') {
            $group = CoachGroup::query()
                ->where('id', $groupId)
                ->where(function ($builder) use ($user): void {
                    $builder->where('coach_id', (string) $user->id)
                        ->orWhereJsonContains('coach_ids', (string) $user->id);
                })
                ->firstOrFail();
            if ($groupName === '') {
                $groupName = $group->name;
            }
        }

        $relation = DB::transaction(function () use ($user, $validated, $groupId, $groupName): CoachMentee {
            $relation = CoachMentee::query()->firstOrNew([
                'coach_id' => (string) $user->id,
                'mentee_id' => trim((string) $validated['mentee_id']),
            ]);

            $previousGroupId = (string) ($relation->group_id ?? '');
            $nextGroupId = $groupId;

            $relation->mentee_name = trim((string) ($validated['mentee_name'] ?? '')) ?: $relation->mentee_name;
            $relation->mentee_email = trim((string) ($validated['mentee_email'] ?? '')) ?: $relation->mentee_email;
            $relation->team_name = trim((string) $validated['team_name']);
            $relation->group_id = $nextGroupId !== '' ? $nextGroupId : null;
            $relation->group_name = $groupName !== '' ? $groupName : null;
            $relation->save();

            $this->syncGroupCounters($previousGroupId, $nextGroupId);

            return $relation->fresh();
        });

        return response()->json([
            'mentee' => $this->menteePayload($relation),
        ]);
    }

    public function removeMentee(Request $request, string $menteeId): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $relation = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->where('mentee_id', $menteeId)
            ->first();

        if ($relation === null) {
            return response()->json(['message' => 'Not found.'], Response::HTTP_NOT_FOUND);
        }

        $previousGroupId = (string) ($relation->group_id ?? '');

        DB::transaction(function () use ($relation, $user, $previousGroupId): void {
            $relation->delete();
            $this->syncGroupCounters((string) $user->id, $previousGroupId, '');
        });

        $requestId = $this->requestId($menteeId, (string) $user->id);
        $coachRequest = CoachRequest::query()->find($requestId);
        if ($coachRequest !== null) {
            $coachRequest->status = 'removed';
            $coachRequest->updated_at = now();
            $coachRequest->save();
        }

        return response()->json(['message' => 'Removed.']);
    }

    public function requests(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $requests = CoachRequest::query()
            ->where('coach_id', (string) $user->id)
            ->orderByDesc('updated_at')
            ->get()
            ->map(fn (CoachRequest $coachRequest) => $this->requestPayload($coachRequest));

        return response()->json(['requests' => $requests]);
    }

    public function latestTracker(Request $request, string $menteeId): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $isRelatedMentee = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->where('mentee_id', $menteeId)
            ->exists();
        if (! $isRelatedMentee) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $tracker = DailyTracker::query()
            ->where('user_id', $menteeId)
            ->orderByDesc('date')
            ->orderByDesc('updated_at')
            ->first();

        return response()->json([
            'tracker' => $tracker ? $this->latestTrackerPayload($tracker) : null,
        ]);
    }

    public function trackers(Request $request, string $menteeId): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $isRelatedMentee = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->where('mentee_id', $menteeId)
            ->exists();
        if (! $isRelatedMentee) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'month' => ['nullable', 'date_format:Y-m'],
        ]);

        $month = $validated['month'] ?? now()->format('Y-m');
        $parsedMonth = Carbon::createFromFormat('Y-m', $month);

        $trackers = DailyTracker::query()
            ->where('user_id', $menteeId)
            ->whereYear('date', $parsedMonth->year)
            ->whereMonth('date', $parsedMonth->month)
            ->orderBy('date')
            ->orderBy('updated_at')
            ->get()
            ->map(fn (DailyTracker $tracker) => $this->latestTrackerPayload($tracker))
            ->values();

        return response()->json([
            'trackers' => $trackers,
        ]);
    }

    public function storeRequest(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'coach_id' => ['required', 'string', 'max:255'],
            'coach_name' => ['required', 'string', 'max:255'],
            'coach_email' => ['nullable', 'email', 'max:255'],
            'applicant_role' => ['nullable', 'string', 'max:80'],
            'applicant_is_coach' => ['nullable', 'boolean'],
            'applying_as' => ['nullable', 'string', 'max:80'],
            'status' => ['nullable', 'string', 'max:40'],
            'group_id' => ['nullable', 'string', 'max:255'],
            'group_name' => ['nullable', 'string', 'max:255'],
            'mentee_name' => ['nullable', 'string', 'max:255'],
            'mentee_email' => ['nullable', 'email', 'max:255'],
        ]);

        $coachId = trim((string) $validated['coach_id']);
        $requestId = $this->requestId((string) $user->id, $coachId);
        $coachRequest = CoachRequest::query()->updateOrCreate(
            ['id' => $requestId],
            [
                'coach_id' => $coachId,
                'coach_name' => trim((string) $validated['coach_name']),
                'coach_email' => trim((string) ($validated['coach_email'] ?? '')) ?: null,
                'mentee_id' => (string) $user->id,
                'mentee_name' => trim((string) ($validated['mentee_name'] ?? $user->name)),
                'mentee_email' => trim((string) ($validated['mentee_email'] ?? $user->email)),
                'applicant_role' => trim((string) ($validated['applicant_role'] ?? $user->role)),
                'applicant_is_coach' => (bool) ($validated['applicant_is_coach'] ?? $user->is_coach),
                'applying_as' => trim((string) ($validated['applying_as'] ?? 'mentee')),
                'status' => trim((string) ($validated['status'] ?? 'pending')),
                'group_id' => trim((string) ($validated['group_id'] ?? '')) ?: null,
                'group_name' => trim((string) ($validated['group_name'] ?? '')) ?: null,
                'company_code' => $user->company_code,
                'company_name' => $user->company_name,
            ]
        );

        return response()->json([
            'request' => $this->requestPayload($coachRequest->fresh()),
        ], Response::HTTP_CREATED);
    }

    public function acceptRequest(Request $request, string $requestId): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'team_name' => ['required', 'string', 'max:255'],
            'group_id' => ['nullable', 'string', 'exists:coach_groups,id'],
            'group_name' => ['nullable', 'string', 'max:255'],
        ]);

        $coachRequest = CoachRequest::query()
            ->where('id', $requestId)
            ->where('coach_id', (string) $user->id)
            ->firstOrFail();

        $groupId = trim((string) ($validated['group_id'] ?? ''));
        $groupName = trim((string) ($validated['group_name'] ?? ''));
        if ($groupId !== '') {
            $group = CoachGroup::query()
                ->where('id', $groupId)
                ->where(function ($builder) use ($user): void {
                    $builder->where('coach_id', (string) $user->id)
                        ->orWhereJsonContains('coach_ids', (string) $user->id);
                })
                ->firstOrFail();
            if ($groupName === '') {
                $groupName = $group->name;
            }
        }

        DB::transaction(function () use ($user, $coachRequest, $validated, $groupId, $groupName): void {
            $relation = CoachMentee::query()->firstOrNew([
                'coach_id' => (string) $user->id,
                'mentee_id' => (string) $coachRequest->mentee_id,
            ]);

            $previousGroupId = (string) ($relation->group_id ?? '');
            $nextGroupId = $groupId;

            $relation->mentee_name = $coachRequest->mentee_name;
            $relation->mentee_email = $coachRequest->mentee_email;
            $relation->team_name = trim((string) $validated['team_name']);
            $relation->group_id = $nextGroupId !== '' ? $nextGroupId : null;
            $relation->group_name = $groupName !== '' ? $groupName : null;
            $relation->save();

            $this->syncGroupCounters($previousGroupId, $nextGroupId);

            $coachRequest->status = 'accepted';
            $coachRequest->group_id = $groupId !== '' ? $groupId : null;
            $coachRequest->group_name = $groupName !== '' ? $groupName : null;
            $coachRequest->accepted_at = now();
            $coachRequest->updated_at = now();
            $coachRequest->save();
        });

        return response()->json([
            'request' => $this->requestPayload($coachRequest->fresh()),
        ]);
    }

    public function declineRequest(Request $request, string $requestId): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $coachRequest = CoachRequest::query()
            ->where('id', $requestId)
            ->where('coach_id', (string) $user->id)
            ->firstOrFail();

        $coachRequest->status = 'rejected';
        $coachRequest->updated_at = now();
        $coachRequest->save();

        return response()->json([
            'request' => $this->requestPayload($coachRequest->fresh()),
        ]);
    }

    private function syncGroupCounters(string $previousGroupId, string $nextGroupId): void
    {
        if ($previousGroupId !== '' && $previousGroupId !== $nextGroupId) {
            CoachGroup::query()
                ->where('id', $previousGroupId)
                ->decrement('member_count');
        }

        if ($nextGroupId !== '' && $previousGroupId !== $nextGroupId) {
            CoachGroup::query()
                ->where('id', $nextGroupId)
                ->increment('member_count');
        }
    }

    private function groupPayload(CoachGroup $group): array
    {
        $coachIds = $this->groupCoachIds($group);
        $memberIds = CoachMentee::query()
            ->whereIn('coach_id', $coachIds)
            ->where('group_id', $group->id)
            ->pluck('mentee_id')
            ->map(static fn ($id) => (string) $id)
            ->values()
            ->all();

        $coachNames = User::query()
            ->whereIn('id', $coachIds)
            ->orderBy('name')
            ->pluck('name')
            ->map(static fn ($name) => (string) $name)
            ->values()
            ->all();

        return [
            'id' => $group->id,
            'coachId' => (string) $group->coach_id,
            'coachIds' => $coachIds,
            'coachNames' => $coachNames,
            'coachCount' => count($coachIds),
            'name' => $group->name,
            'memberIds' => $memberIds,
            'memberCount' => count($memberIds),
            'companyCode' => $group->company_code,
            'companyName' => $group->company_name,
            'createdAt' => $group->created_at?->toIso8601String(),
            'updatedAt' => $group->updated_at?->toIso8601String(),
        ];
    }

    private function menteePayload(CoachMentee $relation): array
    {
        return [
            'coachId' => (string) $relation->coach_id,
            'menteeId' => (string) $relation->mentee_id,
            'menteeName' => $relation->mentee_name,
            'menteeEmail' => $relation->mentee_email,
            'teamName' => $relation->team_name,
            'groupId' => $relation->group_id,
            'groupName' => $relation->group_name,
            'createdAt' => $relation->created_at?->toIso8601String(),
            'updatedAt' => $relation->updated_at?->toIso8601String(),
        ];
    }

    private function requestPayload(CoachRequest $request): array
    {
        return [
            'id' => $request->id,
            'coachId' => (string) $request->coach_id,
            'coachName' => $request->coach_name,
            'coachEmail' => $request->coach_email,
            'menteeId' => (string) $request->mentee_id,
            'menteeName' => $request->mentee_name,
            'menteeEmail' => $request->mentee_email,
            'applicantRole' => $request->applicant_role,
            'applicantIsCoach' => (bool) $request->applicant_is_coach,
            'applyingAs' => $request->applying_as,
            'status' => $request->status,
            'groupId' => $request->group_id,
            'groupName' => $request->group_name,
            'companyCode' => $request->company_code,
            'companyName' => $request->company_name,
            'acceptedAt' => $request->accepted_at?->toIso8601String(),
            'createdAt' => $request->created_at?->toIso8601String(),
            'updatedAt' => $request->updated_at?->toIso8601String(),
        ];
    }

    private function latestTrackerPayload(DailyTracker $tracker): array
    {
        return [
            'id' => (string) $tracker->id,
            'userId' => (string) $tracker->user_id,
            'username' => $tracker->username,
            'date' => $tracker->date?->toDateString(),
            'stepCount' => $tracker->step_count,
            'stepGoal' => $tracker->step_goal,
            'meditation' => $tracker->meditation,
            'steps' => $tracker->steps,
            'call' => $tracker->call,
            'exercise' => $tracker->exercise,
            'learning' => $tracker->learning,
            'addValue' => $tracker->add_value,
            'todoList' => $tracker->todo_list,
            'meditationMinutes' => $tracker->meditation_minutes,
            'callCount' => $tracker->call_count,
            'exerciseCount' => $tracker->exercise_count,
            'exerciseMinutes' => $tracker->exercise_minutes,
            'learningCount' => $tracker->learning_count,
            'valueCount' => $tracker->value_count,
            'todoListCount' => $tracker->todo_list_count,
            'todoListScore' => $tracker->todo_list_score,
            'todoListScoreDailyContribution' => $tracker->todo_list_score_daily_contribution,
            'todoListIncludedInTotal' => $tracker->todo_list_included_in_total,
            'userTotalScore' => $tracker->user_total_score,
            'customDailyTasks' => $tracker->custom_daily_tasks,
            'companyId' => $tracker->company_id,
            'companyCode' => $tracker->company_code,
            'companyName' => $tracker->company_name,
            'createdAt' => $tracker->created_at?->toIso8601String(),
            'updatedAt' => $tracker->updated_at?->toIso8601String(),
        ];
    }

    private function requestId(string $menteeId, string $coachId): string
    {
        return $menteeId.'_'.$coachId;
    }

    private function isAdmin(User $user): bool
    {
        $role = strtolower(trim((string) $user->role));
        return $role === 'admin' || (bool) $user->is_admin;
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
     * @return array<int, string>
     */
    private function groupCoachIds(CoachGroup $group): array
    {
        $coachIds = [(string) $group->coach_id];
        foreach (is_array($group->coach_ids) ? $group->coach_ids : [] as $coachId) {
            $coachIds[] = trim((string) $coachId);
        }

        return array_values(array_unique(array_filter($coachIds)));
    }

    private function userCanManageGroup(User $user, CoachGroup $group): bool
    {
        return (string) $group->coach_id === (string) $user->id
            || in_array((string) $user->id, $this->groupCoachIds($group), true);
    }
}
