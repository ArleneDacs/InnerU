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
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

class LeaderboardController extends Controller
{
    public function __construct(private readonly UserScoreService $userScoreService) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $company = $this->resolveCompany($user);
        $isCoach = (bool) $user->is_coach;

        $companyUsers = $this->companyUsersForScope($company, $user);

        $companyScores = $this->userScoreService->resolveBreakdownForUsers($companyUsers, $company);
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
                    if ($this->companyIdentifierMatches($group->company_id, $company)) {
                        return true;
                    }

                    $groupCode = $this->normalizedCode($group->company_code);
                    if ($groupCode !== '' && $groupCode === $this->normalizedCode($company->code)) {
                        return true;
                    }

                    // Fall back to checking whether the coach/members
                    // currently resolve into the viewer's company, for
                    // groups with no company_id/code/name stamped at all.
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
            ->map(function (CoachGroup $group) use ($companyScores, $company) {
                $coachIds = $this->groupCoachIds($group);
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

                // The group itself has already been confirmed to belong to
                // the viewer's company (see the filter above). Its coach and
                // members are trusted by that association, so look them up
                // directly instead of requiring their own company fields to
                // independently resolve into $usersById -- otherwise a coach
                // or member with blank/messy company data (the same pattern
                // already fixed for the viewer) would be silently dropped
                // even though the group they belong to matched correctly.
                $groupUsersById = User::query()
                    ->whereIn('id', array_unique(array_merge($coachIds, $memberIds)))
                    ->get()
                    ->keyBy(fn (User $candidate) => (string) $candidate->id);

                $coachNames = collect($coachIds)
                    ->map(fn (string $coachId) => $groupUsersById->get($coachId)?->name)
                    ->filter()
                    ->values()
                    ->all();
                $coachName = $coachNames === [] ? 'Coach' : implode(', ', $coachNames);

                $entries = collect($memberIds)
                    ->map(function (string $memberId) use ($groupUsersById, $group, $companyScores): ?array {
                        $member = $groupUsersById->get($memberId);
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
                    'photoUrl' => $group->photo_url,
                    'coachName' => $coachName,
                    'coachIds' => $coachIds,
                    'coachNames' => $coachNames,
                    'companyId' => $company?->id,
                    'companyName' => $company?->name,
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
     * @param  array<string, array{goalScore:float, coreTaskScore:float, overallScore:float}>  $breakdowns
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
            $candidate = trim($candidate);
            $company = Company::query()
                ->where('id', $candidate)
                ->orWhereRaw('UPPER(TRIM(code)) = ?', [$this->normalizedCode($candidate)])
                ->orWhereRaw('LOWER(TRIM(name)) = ?', [$this->normalizedName($candidate)])
                ->first();

            if ($company !== null) {
                return $company;
            }
        }

        return null;
    }

    /**
     * @return Collection<int, User>
     */
    private function companyUsersForScope(?Company $company, User $viewer): Collection
    {
        if ($company === null) {
            return collect([$viewer]);
        }

        // Imported Firestore users can still have the old company code in
        // an *_company_id field, while companies now use UUID primary keys.
        // Both values identify the same company.
        $identifierUsers = User::query()
            ->where(function ($builder) use ($company): void {
                $identifiers = [
                    $this->normalizedCode($company->id),
                    $this->normalizedCode($company->code),
                ];
                $builder->whereIn(DB::raw('UPPER(TRIM(company_id))'), $identifiers)
                    ->orWhereIn(DB::raw('UPPER(TRIM(active_company_id))'), $identifiers);
            })
            ->orderBy('name')
            ->get();

        // company_code is the safest fallback for legacy or partially
        // migrated users: it is unique per company and should still pull in
        // the user even if their company_id has drifted elsewhere.
        $codeUsers = User::query()
            ->where(function ($builder) use ($company): void {
                $normalizedCode = $this->normalizedCode($company->code);
                $builder->whereRaw('UPPER(TRIM(company_code)) = ?', [$normalizedCode])
                    ->orWhereRaw('UPPER(TRIM(active_company_code)) = ?', [$normalizedCode]);
            })
            ->orderBy('name')
            ->get();

        // company_name is only trusted when no definitive company id is
        // present on the user record. Names are not unique, so they stay the
        // last-resort fallback for the messy legacy records that still need a
        // leaderboard until their data is cleaned up.
        $nameUsers = User::query()
            ->where(function ($builder): void {
                $builder->whereNull('company_id')->orWhere('company_id', '');
            })
            ->where(function ($builder): void {
                $builder->whereNull('active_company_id')->orWhere('active_company_id', '');
            })
            ->where(function ($builder) use ($company): void {
                $normalizedName = $this->normalizedName($company->name);
                $builder->whereRaw('LOWER(TRIM(company_name)) = ?', [$normalizedName])
                    ->orWhereRaw('LOWER(TRIM(active_company_name)) = ?', [$normalizedName]);
            })
            ->orderBy('name')
            ->get();

        // Newer mobile/profile sync flows can persist company membership
        // details in the JSON array columns instead of the legacy direct
        // company_id/company_code/company_name fields. Keep those users in
        // scope too so the leaderboard still renders for partially
        // migrated accounts.
        $membershipUsers = User::query()
            ->where(function ($builder): void {
                $builder->whereNotNull('company_memberships')
                    ->orWhereNotNull('company_ids')
                    ->orWhereNotNull('company_codes');
            })
            ->orderBy('name')
            ->get()
            ->filter(fn (User $candidate): bool => $this->userBelongsToCompany($candidate, $company));

        // Union both, don't short-circuit on the exact-id match alone: a
        // user resolved into this company only via code/name (e.g. their
        // own company_id is blank) must not be hidden just because some
        // OTHER user in the same company happens to have a clean
        // company_id. Without this, the viewer themselves could vanish
        // from their own company's leaderboard whenever anyone else in
        // the company has tidier data than they do.
        $combined = $identifierUsers
            ->concat($codeUsers)
            ->concat($nameUsers)
            ->concat($membershipUsers)
            ->filter(fn (User $candidate): bool => $this->userBelongsToCompany($candidate, $company))
            ->unique(fn (User $candidate) => (string) $candidate->id)
            ->values();

        if (! $combined->contains(fn (User $candidate) => (string) $candidate->id === (string) $viewer->id)) {
            $combined = $combined->push($viewer)->values();
        }

        return $combined;
    }

    private function userBelongsToCompany(User $user, Company $company): bool
    {
        if ($this->companyIdentifierMatches($user->company_id, $company)) {
            return true;
        }

        if ($this->companyIdentifierMatches($user->active_company_id, $company)) {
            return true;
        }

        $companyCode = $this->normalizedCode($company->code);
        if ($companyCode !== '' && $this->normalizedCode($user->company_code) === $companyCode) {
            return true;
        }

        if ($companyCode !== '' && $this->normalizedCode($user->active_company_code) === $companyCode) {
            return true;
        }

        if ($this->companyMembershipMatches($user->company_memberships, $company)) {
            return true;
        }

        if ($this->companyIdArrayMatches($user->company_ids, (string) $company->id)) {
            return true;
        }

        if ($this->companyCodeArrayMatches($user->company_ids, (string) $company->code)) {
            return true;
        }

        if ($this->companyCodeArrayMatches($user->company_codes, (string) $company->code)) {
            return true;
        }

        // Names are not unique. Only use one when no id is available.
        if (trim((string) $user->company_id) !== '' || trim((string) $user->active_company_id) !== '') {
            return false;
        }

        $companyName = $this->normalizedName($company->name);

        return $companyName !== ''
            && ($this->normalizedName($user->company_name) === $companyName
                || $this->normalizedName($user->active_company_name) === $companyName);
    }

    private function groupBelongsToCompany(CoachGroup $group, Company $company): bool
    {
        if ($this->companyIdentifierMatches($group->company_id, $company)) {
            return true;
        }

        if ($this->normalizedCode($group->company_code) === $this->normalizedCode($company->code)) {
            return true;
        }

        return $this->normalizedName($group->company_name) === $this->normalizedName($company->name);
    }

    /**
     * @return array<int, string>
     */
    private function companyLookupCandidates(User $user): array
    {
        $candidates = [
            trim((string) $user->active_company_id),
            trim((string) $user->active_company_code),
            trim((string) $user->active_company_name),
            trim((string) $user->company_id),
            trim((string) $user->company_code),
            trim((string) $user->company_name),
        ];

        foreach (is_array($user->company_ids) ? $user->company_ids : [] as $companyId) {
            $candidates[] = trim((string) $companyId);
        }

        foreach (is_array($user->company_codes) ? $user->company_codes : [] as $companyCode) {
            $candidates[] = trim((string) $companyCode);
        }

        foreach (is_array($user->company_memberships) ? $user->company_memberships : [] as $membership) {
            if (is_string($membership) || is_numeric($membership)) {
                $candidates[] = trim((string) $membership);

                continue;
            }

            if (! is_array($membership)) {
                continue;
            }

            $candidates[] = trim((string) (
                $membership['companyId'] ?? $membership['company_id'] ?? $membership['id'] ?? ''
            ));
            $candidates[] = trim((string) (
                $membership['companyCode'] ?? $membership['company_code'] ?? $membership['code'] ?? ''
            ));
            $candidates[] = trim((string) (
                $membership['companyName'] ?? $membership['company_name'] ?? $membership['name'] ?? ''
            ));
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

    private function companyIdArrayMatches(mixed $values, string $companyId): bool
    {
        if (! is_array($values)) {
            return false;
        }

        $normalizedCompanyId = trim($companyId);
        foreach ($values as $value) {
            if (trim((string) $value) === $normalizedCompanyId) {
                return true;
            }
        }

        return false;
    }

    private function companyCodeArrayMatches(mixed $values, string $companyCode): bool
    {
        if (! is_array($values)) {
            return false;
        }

        $normalizedCompanyCode = strtoupper(trim($companyCode));
        foreach ($values as $value) {
            if (strtoupper(trim((string) $value)) === $normalizedCompanyCode) {
                return true;
            }
        }

        return false;
    }

    private function companyMembershipMatches(mixed $memberships, Company $company): bool
    {
        if (! is_array($memberships)) {
            return false;
        }

        foreach ($memberships as $membership) {
            if (is_string($membership) || is_numeric($membership)) {
                if ($this->companyIdentifierMatches($membership, $company)) {
                    return true;
                }

                continue;
            }

            if (! is_array($membership)) {
                continue;
            }

            $membershipCompanyId = trim((string) (
                $membership['companyId']
                ?? $membership['company_id']
                ?? $membership['id']
                ?? ''
            ));
            $membershipCompanyCode = strtoupper(trim((string) (
                $membership['companyCode']
                ?? $membership['company_code']
                ?? $membership['code']
                ?? ''
            )));
            $membershipCompanyName = trim((string) (
                $membership['companyName']
                ?? $membership['company_name']
                ?? $membership['name']
                ?? ''
            ));

            if ($this->companyIdentifierMatches($membershipCompanyId, $company)) {
                return true;
            }

            if ($membershipCompanyCode !== '' && $membershipCompanyCode === $this->normalizedCode($company->code)) {
                return true;
            }

            if ($membershipCompanyName !== ''
                && $this->normalizedName($membershipCompanyName) === $this->normalizedName($company->name)
            ) {
                return true;
            }
        }

        return false;
    }

    private function companyIdentifierMatches(mixed $value, Company $company): bool
    {
        $normalizedValue = $this->normalizedCode($value);
        if ($normalizedValue === '') {
            return false;
        }

        return $normalizedValue === $this->normalizedCode($company->id)
            || $normalizedValue === $this->normalizedCode($company->code);
    }

    private function normalizedCode(mixed $value): string
    {
        return strtoupper(trim((string) ($value ?? '')));
    }

    private function normalizedName(mixed $value): string
    {
        return strtolower(trim((string) ($value ?? '')));
    }
}
