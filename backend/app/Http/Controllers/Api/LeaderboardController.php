<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CoachGroup;
use App\Models\CoachMentee;
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

        $companyId = $this->activeCompanyValue($user->active_company_id, $user->company_id);
        $companyCode = $this->activeCompanyValue($user->active_company_code, $user->company_code);
        $companyName = $this->activeCompanyValue($user->active_company_name, $user->company_name);
        $isCoach = (bool) $user->is_coach;
        $hasResolvedCompany = $companyId !== '' || $companyCode !== '' || $companyName !== '';

        // When none of a viewer's company identifiers can be resolved, the
        // matching closure below would add zero conditions, and an
        // unconstrained nested `where` matches every row — i.e. every user
        // on the platform, leaking every other company's names, scores,
        // and profile pictures. Fail closed (the viewer only sees
        // themselves) instead of fail open.
        $companyUsers = $hasResolvedCompany
            ? User::query()
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
            : collect([$user]);

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

        $groupLeaderboards = CoachGroup::query()
            ->orderBy('name')
            ->get()
            ->filter(function (CoachGroup $group) use ($companyId, $companyCode, $companyName, $usersById): bool {
                $coachIds = $this->groupCoachIds($group);
                $groupCoachIsInCompany = collect($coachIds)->contains(function (string $coachId) use ($usersById, $companyId, $companyCode, $companyName): bool {
                    $coach = $usersById->get($coachId);
                    if ($coach === null) {
                        return false;
                    }

                    return $this->belongsToCompany($coach->company_id ?? null, $coach->company_code ?? '', $coach->company_name ?? '', $companyId, $companyCode, $companyName);
                });

                return $this->belongsToCompany($group->company_id ?? null, $group->company_code ?? '', $group->company_name ?? '', $companyId, $companyCode, $companyName)
                    || $groupCoachIsInCompany;
            })
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
                'companyId' => $companyId,
                'companyCode' => $companyCode,
                'companyName' => $companyName,
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

    private function belongsToCompany(
        ?string $companyId,
        string $companyCode,
        string $companyName,
        string $targetCompanyId,
        string $targetCompanyCode,
        string $targetCompanyName,
    ): bool {
        if ($targetCompanyId !== '' && $companyId !== null && trim($companyId) === $targetCompanyId) {
            return true;
        }

        if ($targetCompanyCode !== '' && $companyCode !== '' && trim($companyCode) === $targetCompanyCode) {
            return true;
        }

        if ($targetCompanyName !== '' && $companyName !== '' && trim($companyName) === $targetCompanyName) {
            return true;
        }

        return false;
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
