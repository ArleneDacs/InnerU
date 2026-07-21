<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class LeaderboardController extends Controller
{
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

        $query = User::query()
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
            ->orderByDesc('score')
            ->orderBy('name');

        $companyLeaderboard = $query->get()->map(function (User $candidate, int $index) {
            return [
                'userId' => (string) $candidate->id,
                'name' => $candidate->name,
                'score' => (int) $candidate->score,
                'rank' => $index + 1,
                'profilePic' => $candidate->profile_pic,
                'teamName' => $candidate->company_name,
            ];
        });

        $usersById = User::query()
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
            ->get()
            ->keyBy(fn (User $candidate) => (string) $candidate->id);

        $groupLeaderboards = CoachGroup::query()
            ->orderBy('name')
            ->get()
            ->filter(function (CoachGroup $group) use ($companyId, $companyCode, $companyName, $usersById): bool {
                $coach = $usersById->get((string) $group->coach_id);
                if ($coach === null) {
                    return false;
                }

                return $this->belongsToCompany($group->company_id ?? null, $group->company_code ?? '', $group->company_name ?? '', $companyId, $companyCode, $companyName)
                    || $this->belongsToCompany($coach->company_id ?? null, $coach->company_code ?? '', $coach->company_name ?? '', $companyId, $companyCode, $companyName);
            })
            ->map(function (CoachGroup $group) use ($usersById) {
                $coach = $usersById->get((string) $group->coach_id);
                $coachName = $coach?->name ?? 'Coach';
                $memberIds = CoachMentee::query()
                    ->where('coach_id', (string) $group->coach_id)
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
                    ->map(function (string $memberId) use ($usersById, $group): ?array {
                        $member = $usersById->get($memberId);
                        if ($member === null) {
                            return null;
                        }

                        return [
                            'userId' => (string) $member->id,
                            'name' => $member->name,
                            'score' => (int) $member->score,
                            'profilePic' => $member->profile_pic,
                            'teamName' => $group->name,
                        ];
                    })
                    ->filter()
                    ->sortByDesc('score')
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
                    'totalScore' => $totalScore,
                    'entries' => $entries,
                ];
            })
            ->values();

        $menteeEntries = CoachMentee::query()
            ->where('coach_id', (string) $user->id)
            ->orderByDesc('updated_at')
            ->get()
            ->map(function (CoachMentee $relation) use ($usersById): ?array {
                $mentee = $usersById->get((string) $relation->mentee_id);
                if ($mentee === null) {
                    return null;
                }

                return [
                    'userId' => (string) $mentee->id,
                    'name' => $mentee->name,
                    'score' => (int) $mentee->score,
                    'rank' => 0,
                    'profilePic' => $mentee->profile_pic,
                    'teamName' => $relation->group_name ?: $relation->team_name,
                ];
            })
            ->filter()
            ->sortByDesc('score')
            ->values()
            ->map(function (array $entry, int $index): array {
                $entry['rank'] = $index + 1;
                return $entry;
            })
            ->values();

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
                'score' => (int) $user->score,
                'isCoach' => $isCoach,
            ],
        ]);
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
}
