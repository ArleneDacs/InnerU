<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AccountabilityMeeting;
use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\DailyTracker;
use App\Models\MeetingAttendance;
use App\Models\User;
use App\Services\AccountabilityMeetingReminderService;
use App\Services\UserScoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class AccountabilityMeetingController extends Controller
{
    public function __construct(
        private readonly UserScoreService $userScoreService,
        private readonly AccountabilityMeetingReminderService $reminderService,
    ) {}

    /**
     * A group coach or a current group member schedules a recurring/one-off
     * accountability meeting. No notifications are sent here — the
     * day-before / day-of sweep (see AccountabilityMeetingReminderService)
     * is the only notifier, so that group members aren't spammed the moment
     * a meeting is created regardless of how far out it is.
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'group_id' => ['required', 'string', 'exists:coach_groups,id'],
            'title' => ['required', 'string', 'max:255'],
            'zoom_link' => ['required', 'string', 'max:500', 'url'],
            'scheduled_at' => ['required', 'date', 'after:now'],
            'notes' => ['nullable', 'string', 'max:1000'],
        ]);

        $group = CoachGroup::query()->find($validated['group_id']);

        if ($group === null || ! $this->canScheduleForGroup($user, $group)) {
            return response()->json(['message' => 'You must belong to this group to schedule a meeting.'], Response::HTTP_FORBIDDEN);
        }

        $meeting = AccountabilityMeeting::create([
            'id' => (string) Str::uuid(),
            // This legacy column is the meeting creator identifier. It keeps
            // its established name so existing coach-created meetings and
            // clients remain compatible; it may now contain a member ID.
            'coach_id' => (string) $user->id,
            'group_id' => (string) $group->id,
            'title' => $validated['title'],
            'zoom_link' => $validated['zoom_link'],
            'notes' => $validated['notes'] ?? null,
            'scheduled_at' => $validated['scheduled_at'],
            'day_before_notified_at' => null,
            'day_of_notified_at' => null,
        ]);

        return response()->json([
            'meeting' => $this->payload(
                $meeting,
                groupName: $group->name,
                isCreator: true,
            ),
        ], Response::HTTP_CREATED);
    }

    public function update(Request $request, AccountabilityMeeting $accountabilityMeeting): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if (! $this->isMeetingCreator($user, $accountabilityMeeting)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_FORBIDDEN);
        }

        $validated = $request->validate([
            'title' => ['required', 'string', 'max:255'],
            'zoom_link' => ['required', 'string', 'max:500', 'url'],
            'scheduled_at' => ['required', 'date'],
            'notes' => ['nullable', 'string', 'max:1000'],
        ]);

        $accountabilityMeeting->update([
            'title' => $validated['title'],
            'zoom_link' => $validated['zoom_link'],
            'notes' => $validated['notes'] ?? null,
            'scheduled_at' => $validated['scheduled_at'],
        ]);

        $group = CoachGroup::query()->find((string) $accountabilityMeeting->group_id);

        return response()->json([
            'meeting' => $this->payload(
                $accountabilityMeeting->refresh(),
                groupName: $group?->name,
            ),
        ]);
    }

    public function destroy(Request $request, AccountabilityMeeting $accountabilityMeeting): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        if (! $this->isMeetingCreator($user, $accountabilityMeeting)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_FORBIDDEN);
        }

        DB::transaction(function () use ($accountabilityMeeting): void {
            MeetingAttendance::query()
                ->where('meeting_id', (string) $accountabilityMeeting->id)
                ->delete();

            $accountabilityMeeting->delete();
        });

        return response()->json(['message' => 'Meeting deleted.']);
    }

    /**
     * Meetings visible to an authenticated coach: every meeting scheduled
     * for a group they manage, plus anything they personally created. A
     * meeting can therefore be created by a member without hiding it from
     * the group's coaches. Editing/deletion remains creator-only.
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $this->reminderService->sweepDueReminders();

        $managedGroupIds = $this->managedGroupIds($user);

        $meetings = AccountabilityMeeting::query()
            ->where(function ($builder) use ($user, $managedGroupIds): void {
                $builder->where('coach_id', (string) $user->id)
                    ->orWhereIn('group_id', $managedGroupIds);
            })
            ->orderBy('scheduled_at')
            ->get();

        $groupIds = $meetings->pluck('group_id')->unique()->values();

        $menteeCounts = CoachMentee::query()
            ->whereIn('group_id', $groupIds)
            ->selectRaw('group_id, count(*) as aggregate')
            ->groupBy('group_id')
            ->pluck('aggregate', 'group_id');

        $groupNames = CoachGroup::query()->whereIn('id', $groupIds)->pluck('name', 'id');

        return response()->json([
            'meetings' => $meetings->map(fn (AccountabilityMeeting $meeting) => $this->payload(
                $meeting,
                groupName: $groupNames[$meeting->group_id] ?? null,
                menteeCount: (int) ($menteeCounts[$meeting->group_id] ?? 0),
                isCreator: $this->isMeetingCreator($user, $meeting),
            ))->values(),
        ]);
    }

    /**
     * Meetings for every group the authenticated user participates in:
     * either as a current member or as one of that group's coaches. This is
     * also the destination for meeting reminder taps, so a coach never lands
     * on an empty list for a meeting they were notified about.
     */
    public function mine(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $this->reminderService->sweepDueReminders();

        $memberGroupIds = CoachMentee::query()
            ->where('mentee_id', (string) $user->id)
            ->whereNotNull('group_id')
            ->pluck('group_id');
        $groupIds = $memberGroupIds
            ->merge($this->managedGroupIds($user))
            ->filter()
            ->unique()
            ->values();

        $meetings = AccountabilityMeeting::query()
            ->whereIn('group_id', $groupIds)
            ->orderBy('scheduled_at')
            ->get();

        $joinedMeetingIds = MeetingAttendance::query()
            ->where('mentee_id', (string) $user->id)
            ->whereIn('meeting_id', $meetings->pluck('id'))
            ->pluck('meeting_id')
            ->all();

        $groupNames = CoachGroup::query()
            ->whereIn('id', $meetings->pluck('group_id')->unique()->values())
            ->pluck('name', 'id');

        return response()->json([
            'meetings' => $meetings->map(fn (AccountabilityMeeting $meeting) => $this->payload(
                $meeting,
                groupName: $groupNames[$meeting->group_id] ?? null,
                hasJoined: in_array((string) $meeting->id, $joinedMeetingIds, true),
                isCreator: $this->isMeetingCreator($user, $meeting),
            ))->values(),
        ]);
    }

    /**
     * Groups the authenticated user may schedule an accountability meeting
     * for: current memberships and groups they manage as a coach. This
     * deliberately comes from server-side membership/coach records rather
     * than client-provided IDs.
     */
    public function groups(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $memberGroupIds = CoachMentee::query()
            ->where('mentee_id', (string) $user->id)
            ->whereNotNull('group_id')
            ->distinct()
            ->pluck('group_id');
        $groupIds = $memberGroupIds
            ->merge($this->managedGroupIds($user))
            ->filter()
            ->unique()
            ->values();

        $groups = CoachGroup::query()
            ->whereIn('id', $groupIds)
            ->orderBy('name')
            ->get()
            ->map(fn (CoachGroup $group) => [
                'id' => (string) $group->id,
                'name' => $group->name,
                'photoUrl' => $group->photo_url,
            ])
            ->values();

        return response()->json(['groups' => $groups]);
    }

    /**
     * A group member or coach taps "join": records attendance (idempotent
     * — repeat taps don't double-count) and, on the genuinely first join,
     * marks today's "Call" daily-tracker task complete for them before the
     * client is handed the Zoom link to open.
     */
    public function join(Request $request, string $accountabilityMeeting): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $meeting = AccountabilityMeeting::find($accountabilityMeeting);
        if ($meeting === null) {
            return response()->json(['message' => 'Meeting not found.'], Response::HTTP_NOT_FOUND);
        }

        $group = CoachGroup::query()->find($meeting->group_id);
        $isInGroup = $group !== null
            && ($this->isGroupMember($user, $group) || $this->isGroupCoach($user, $group));
        if (! $isInGroup) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $alreadyJoined = false;

        DB::transaction(function () use ($meeting, $user, &$alreadyJoined): void {
            $attendance = MeetingAttendance::firstOrCreate(
                [
                    'meeting_id' => (string) $meeting->id,
                    'mentee_id' => (string) $user->id,
                ],
                [
                    'id' => (string) Str::uuid(),
                    'joined_at' => now(),
                ],
            );

            if (! $attendance->wasRecentlyCreated) {
                $alreadyJoined = true;

                return;
            }

            $date = now()->toDateString();

            $existingTracker = DailyTracker::query()
                ->where('user_id', (string) $user->id)
                ->whereDate('date', $date)
                ->first();

            $tracker = DailyTracker::updateOrCreate(
                [
                    'user_id' => (string) $user->id,
                    'date' => $date,
                ],
                [
                    'username' => $existingTracker?->username ?? $user->name ?? '',
                    'step_count' => $existingTracker?->step_count ?? 0,
                    'step_goal' => $existingTracker?->step_goal ?? 5000,
                    'meditation' => $existingTracker?->meditation ?? false,
                    'steps' => $existingTracker?->steps ?? false,
                    'call' => true,
                    'exercise' => $existingTracker?->exercise ?? false,
                    'learning' => $existingTracker?->learning ?? false,
                    'add_value' => $existingTracker?->add_value ?? false,
                    'todo_list' => $existingTracker?->todo_list ?? false,
                    'call_count' => ($existingTracker?->call_count ?? 0) + 1,
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
                    'company_id' => $existingTracker?->company_id ?? $user->company_code,
                    'company_code' => $existingTracker?->company_code ?? $user->company_code,
                    'company_name' => $existingTracker?->company_name ?? $user->company_name,
                ]
            );

            try {
                $resolvedScore = $this->userScoreService->syncForUser($user);
                $tracker->forceFill(['user_total_score' => $resolvedScore])->save();
            } catch (\Throwable $throwable) {
                report($throwable);
            }
        });

        return response()->json([
            'meeting' => $this->payload($meeting),
            'zoomLink' => $meeting->zoom_link,
            'alreadyJoined' => $alreadyJoined,
        ]);
    }

    private function payload(
        AccountabilityMeeting $meeting,
        ?string $groupName = null,
        ?int $menteeCount = null,
        ?bool $hasJoined = null,
        ?bool $isCreator = null,
    ): array {
        if ($groupName === null) {
            $groupName = CoachGroup::find($meeting->group_id)?->name;
        }

        return [
            'id' => (string) $meeting->id,
            'groupId' => (string) $meeting->group_id,
            'groupName' => $groupName,
            'coachId' => (string) $meeting->coach_id,
            'title' => $meeting->title,
            'zoomLink' => $meeting->zoom_link,
            'notes' => $meeting->notes,
            'scheduledAt' => $meeting->scheduled_at?->toIso8601String(),
            'menteeCount' => $menteeCount,
            'hasJoined' => $hasJoined,
            'isCreator' => $isCreator,
        ];
    }

    private function isMeetingCreator(User $user, AccountabilityMeeting $meeting): bool
    {
        return (string) $meeting->coach_id === (string) $user->id;
    }

    private function canScheduleForGroup(User $user, CoachGroup $group): bool
    {
        return $this->isGroupCoach($user, $group) || $this->isGroupMember($user, $group);
    }

    private function isGroupMember(User $user, CoachGroup $group): bool
    {
        return CoachMentee::query()
            ->where('mentee_id', (string) $user->id)
            ->where('group_id', (string) $group->id)
            ->exists();
    }

    private function isGroupCoach(User $user, CoachGroup $group): bool
    {
        return in_array((string) $user->id, $this->groupCoachIds($group), true);
    }

    /**
     * @return Collection<int, string>
     */
    private function managedGroupIds(User $user): Collection
    {
        return CoachGroup::query()
            ->where(function ($builder) use ($user): void {
                $builder->where('coach_id', (string) $user->id)
                    ->orWhereJsonContains('coach_ids', (string) $user->id);
            })
            ->pluck('id')
            ->map(static fn ($groupId) => (string) $groupId);
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
}
