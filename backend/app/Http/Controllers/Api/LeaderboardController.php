<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\Company;
use App\Models\User;
use App\Services\UserScoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class LeaderboardController extends Controller
{
    public function __construct(private readonly UserScoreService $userScoreService)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $company = $this->resolveCompany($user);
        $isCoach = (bool) $user->is_coach;

        $companyUsers = $this->companyUsersForScope($company, $user);

        $companyScores = $this->userScoreService->resolveBreakdownForUsers($companyUsers);
        $companyLeaderboard = $companyUsers
            ->map(function (User $candidate) use ($companyScores): array {
                $breakdown = $this->leaderboardBreakdownForUser($candidate, $companyScores);

                return [
                    'userId' => (string) $candidate->id,
                    'name' => $candidate->name,
                    'score' => $breakdown['overallScore'],
                    'goalScore' => $breakdown['goalScore'],
                    'coreTaskScore' => $breakdown['coreTaskScore'],
                    'overallScore' => $breakdown['overallScore'],
                    'profilePic' => $candidate->profile_pic,
                    'teamName' => $candidate->company_name,
                ];
            })
            ->sort(function (array $left, array $right): int {
                if ($left['score'] !== $right['score']) {
                    return $right['score'] <=> $left['score'];
                }

                return strcmp($left['name'], $right['name']);
            })
            ->values()
            ->map(function (array $entry, int $index): array {
                $entry['rank'] = $index + 1;
                return $entry;
            })
            ->values();

        $usersById = $companyUsers->keyBy(fn (User $candidate) => (string) $candidate->id);

        $allGroups = CoachGroup::query()->orderBy('name')->get();
        $groupLeaderboards = $company !== null
            ? $allGroups
                ->filter(function (CoachGroup $group) use ($company, $usersById): bool {
                    // The group's own stored company_id (stamped at
                    // creation time from its coach's company) is the
                    // primary signal -- it doesn't drift if the coach's
                    // own record later changes. Fall back to checking
                    // whether the coach/members currently resolve into
                    // the viewer's company, for groups created before
                    // company_id existed or where it's still null.
                    if ($group->company_id !== null
                        && (string) $group->company_id === (string) $company->id
                    ) {
                        return true;
                    }

                    $coachIds = $this->groupCoachIds($group);
                    if (collect($coachIds)->contains(fn (string $coachId): bool => $usersById->has($coachId))) {
                        return true;
                    }

                    $memberIds = is_array($group->member_ids)
                        ? array_values(array_filter(array_map(
                            static fn ($id) => (string) $id,
                            $group->member_ids,
                        )))
                        : [];

                    return collect($memberIds)->contains(
                        fn (string $memberId): bool => $usersById->has($memberId),
                    );
                })
                ->values()
            : collect();

        $groupLeaderboards = $groupLeaderboards
            ->map(function (CoachGroup $group) use ($usersById, $companyScores) {
                $coachIds = $this->groupCoachIds($group);
                $coachNames = collect($coachIds)
                    ->map(fn (string $coachId) => $usersById->get($coachId)?->name)
                    ->filter()
                    ->values()
                    ->all();
                $coachName = $coachNames === [] ? 'Coach' : implode(', ', $coachNames);
                $memberIds = CoachMentee::query()
                    ->whereIn('coach_id', $coachIds)
                    ->where('group_id', $group->id)
                    ->pluck('mentee_id')
                    ->map(static fn ($id) => (string) $id)
                    ->filter()
                    ->values()
                    ->all();

                if ($memberIds === [] && is_array($group->member_ids)) {
                    $memberIds = array_values(array_filter(array_map(
                        static fn ($id) => (string) $id,
                        $group->member_ids,
                    )));
                }

                $entries = collect($memberIds)
                    ->map(function (string $memberId) use ($usersById, $group, $companyScores): ?array {
                        $member = $usersById->get($memberId);
                        if ($member === null) {
                            return null;
                        }

                        $breakdown = $this->leaderboardBreakdownForUser($member, $companyScores);

                        return [
                            'userId' => (string) $member->id,
                            'name' => $member->name,
                            'score' => $breakdown['overallScore'],
                            'goalScore' => $breakdown['goalScore'],
                            'coreTaskScore' => $breakdown['coreTaskScore'],
                            'overallScore' => $breakdown['overallScore'],
                            'profilePic' => $member->profile_pic,
                            'teamName' => $group->name,
                        ];
                    })
                    ->filter()
                    ->sort(function (array $left, array $right): int {
                        if ($left['score'] !== $right['score']) {
                            return $right['score'] <=> $left['score'];
                        }

                        return strcmp($left['name'], $right['name']);
                    })
                    ->values()
                    ->map(function (array $entry, int $index): array {
                        $entry['rank'] = $index + 1;
                        return $entry;
                    })
                    ->values()
                    ->all();

                $totalScore = collect($entries)->sum('score');

                return [
                    'groupId' => $group->id,
                    'groupName' => $group->name,
                    'coachName' => $coachName,
                    'coachIds' => $coachIds,
                    'coachNames' => $coachNames,
                    'totalScore' => $totalScore,
                    'entries' => $entries,
                ];
            })
            ->values();

        $menteeEntries = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->orderByDesc('updated_at')
            ->get()
            ->map(function (CoachMentee $relation) use ($usersById, $companyScores): ?array {
                $mentee = $usersById->get((string) $relation->mentee_id);
                if ($mentee === null) {
                    return null;
                }

                $breakdown = $this->leaderboardBreakdownForUser($mentee, $companyScores);

                return [
                    'userId' => (string) $mentee->id,
                    'name' => $mentee->name,
                    'score' => $breakdown['overallScore'],
                    'goalScore' => $breakdown['goalScore'],
                    'coreTaskScore' => $breakdown['coreTaskScore'],
                    'overallScore' => $breakdown['overallScore'],
                    'rank' => 0,
                    'profilePic' => $mentee->profile_pic,
                    'teamName' => $relation->group_name ?: $relation->team_name,
                ];
            })
            ->filter()
            ->sort(function (array $left, array $right): int {
                if ($left['score'] !== $right['score']) {
                    return $right['score'] <=> $left['score'];
                }

                return strcmp($left['name'], $right['name']);
            })
            ->values()
            ->map(function (array $entry, int $index): array {
                $entry['rank'] = $index + 1;
                return $entry;
            })
            ->values();

        $currentUserBreakdown = $this->leaderboardBreakdownForUser($user, $companyScores);

        return response()->json([
            'company' => [
                'companyId' => $company?->id ?? '',
                'companyCode' => $company?->code ?? '',
                'companyName' => $company?->name ?? '',
                'leaderboardPeriodStart' => optional($company?->leaderboard_period_start)->toDateString(),
                'leaderboardPeriodEnd' => optional($company?->leaderboard_period_end)->toDateString(),
            ],
            'companyLeaderboard' => $companyLeaderboard,
            'entries' => $companyLeaderboard,
            'groupLeaderboards' => $groupLeaderboards,
            'menteeEntries' => $menteeEntries,
            'a12Entries' => [],
            'currentUser' => [
                'userId' => (string) $user->id,
                'name' => $user->name,
                'score' => $currentUserBreakdown['overallScore'],
                'goalScore' => $currentUserBreakdown['goalScore'],
                'coreTaskScore' => $currentUserBreakdown['coreTaskScore'],
                'overallScore' => $currentUserBreakdown['overallScore'],
                'isCoach' => $isCoach,
            ],
        ]);
    }

    /**
     * @param array<string, array{goalScore:float, coreTaskScore:float, overallScore:float}> $breakdowns
     * @return array{goalScore:float, coreTaskScore:float, overallScore:float}
     */
    private function leaderboardBreakdownForUser(User $user, array $breakdowns): array
    {
        $fallback = max(0, min(100, (float) ($user->score ?? 0)));
        $breakdown = $breakdowns[(string) $user->id] ?? null;

        if (! is_array($breakdown)) {
            return [
                'goalScore' => $fallback,
                'coreTaskScore' => 0.0,
                'overallScore' => $fallback,
            ];
        }

        return [
            'goalScore' => (float) ($breakdown['goalScore'] ?? $fallback),
            'coreTaskScore' => (float) ($breakdown['coreTaskScore'] ?? 0.0),
            'overallScore' => (float) ($breakdown['overallScore'] ?? $fallback),
        ];
    }

    private function activeCompanyValue(?string $primary, ?string $fallback): string
    {
        $value = trim((string) ($primary ?? ''));
        if ($value !== '') {
            return $value;
        }

        return trim((string) ($fallback ?? ''));
    }

    private function resolveCompany(?User $user): ?Company
    {
        if ($user === null) {
            return null;
        }

        foreach ($this->companyLookupCandidates($user) as $candidate) {
            $company = Company::query()
                ->where('id', $candidate)
                ->orWhere('code', $candidate)
                ->orWhere('name', $candidate)
                ->first();

            if ($company !== null) {
                return $company;
            }
        }

        return null;
    }

    /**
     * @return \Illuminate\Support\Collection<int, User>
     */
    private function companyUsersForScope(?Company $company, User $viewer): \Illuminate\Support\Collection {
        if ($company === null) {
            return collect([$viewer]);
        }

        $exactCompanyUsers = User::query()
            ->where(function ($builder) use ($company): void {
                $builder->where('company_id', $company->id)
                    ->orWhere('active_company_id', $company->id);
            })
            ->orderBy('name')
            ->get();

        // Code/name is only a valid signal for a user with no definitive
        // company_id at all. A user whose company_id already points at a
        // DIFFERENT company must never be pulled in just because their
        // company_name/company_code happens to collide with this one
        // (e.g. two different companies sharing a display name) -- their
        // own id is authoritative and wins over a name coincidence.
        $codeOrNameUsers = User::query()
            ->where(function ($builder): void {
                $builder->whereNull('company_id')->orWhere('company_id', '');
            })
            ->where(function ($builder): void {
                $builder->whereNull('active_company_id')->orWhere('active_company_id', '');
            })
            ->where(function ($builder) use ($company): void {
                $builder->where('company_code', $company->code)
                    ->orWhere('active_company_code', $company->code)
                    ->orWhere('company_name', $company->name)
                    ->orWhere('active_company_name', $company->name);
            })
            ->orderBy('name')
            ->get();

        // Union both, don't short-circuit on the exact-id match alone: a
        // user resolved into this company only via code/name (e.g. their
        // own company_id is blank) must not be hidden just because some
        // OTHER user in the same company happens to have a clean
        // company_id. Without this, the viewer themselves could vanish
        // from their own company's leaderboard whenever anyone else in
        // the company has tidier data than they do.
        $combined = $exactCompanyUsers
            ->concat($codeOrNameUsers)
            ->unique(fn (User $candidate) => (string) $candidate->id)
            ->values();

        if (! $combined->contains(fn (User $candidate) => (string) $candidate->id === (string) $viewer->id)) {
            $combined = $combined->push($viewer)->values();
        }

        return $combined;
    }

    private function userBelongsToCompany(User $user, Company $company): bool
    {
        if ((string) $user->company_id === (string) $company->id) {
            return true;
        }

        if ((string) $user->active_company_id === (string) $company->id) {
            return true;
        }

        if ((string) $user->company_code === (string) $company->code) {
            return true;
        }

        if ((string) $user->active_company_code === (string) $company->code) {
            return true;
        }

        if ((string) $user->company_name === (string) $company->name) {
            return true;
        }

        return (string) $user->active_company_name === (string) $company->name;
    }

    private function groupBelongsToCompany(CoachGroup $group, Company $company): bool
    {
        if ((string) $group->company_id === (string) $company->id) {
            return true;
        }

        if ((string) $group->company_code === (string) $company->code) {
            return true;
        }

        return (string) $group->company_name === (string) $company->name;
    }

    /**
     * @return array<int, string>
     */
    private function companyLookupCandidates(User $user): array
    {
        $candidates = [
            $this->activeCompanyValue($user->active_company_id, $user->company_id),
            $this->activeCompanyValue($user->active_company_code, $user->company_code),
            $this->activeCompanyValue($user->active_company_name, $user->company_name),
        ];

        foreach (is_array($user->company_ids) ? $user->company_ids : [] as $companyId) {
            $candidates[] = trim((string) $companyId);
        }

        foreach (is_array($user->company_codes) ? $user->company_codes : [] as $companyCode) {
            $candidates[] = trim((string) $companyCode);
        }

        foreach (is_array($user->company_memberships) ? $user->company_memberships : [] as $membership) {
            if (! is_array($membership)) {
                continue;
            }

            $candidates[] = trim((string) ($membership['companyId'] ?? $membership['id'] ?? ''));
            $candidates[] = trim((string) ($membership['companyCode'] ?? $membership['code'] ?? ''));
            $candidates[] = trim((string) ($membership['companyName'] ?? $membership['name'] ?? ''));
        }

        return array_values(array_unique(array_filter($candidates)));
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
