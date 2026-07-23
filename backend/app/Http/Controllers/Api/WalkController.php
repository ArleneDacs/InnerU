<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\RecordedWalk;
use App\Models\WalkInvite;
use App\Models\WalkSession;
use App\Models\WalkSessionMember;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class WalkController extends Controller
{
    public function sessions(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $sessions = WalkSession::query()
            ->orderByDesc('updated_at')
            ->get()
            ->filter(fn (WalkSession $session) => in_array((string) $user->id, array_map('strval', $session->participant_ids ?? []), true))
            ->map(fn (WalkSession $session) => $this->sessionPayload($session));

        return response()->json(['sessions' => $sessions]);
    }

    public function storeSession(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'id' => ['required', 'string', 'max:255'],
            'status' => ['sometimes', 'string', 'max:32'],
            'participant_ids' => ['sometimes', 'array'],
            'created_by' => ['sometimes', 'nullable', 'string', 'max:255'],
            'created_by_name' => ['sometimes', 'nullable', 'string', 'max:255'],
            'company_id' => ['sometimes', 'nullable', 'string', 'max:255'],
            'company_code' => ['sometimes', 'nullable', 'string', 'max:255'],
            'company_name' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        $session = WalkSession::updateOrCreate(
            ['id' => $validated['id']],
            [
                'created_by' => $validated['created_by'] ?? (string) $user->id,
                'created_by_name' => $validated['created_by_name'] ?? $user->name,
                'status' => $validated['status'] ?? 'pending',
                'participant_ids' => $validated['participant_ids'] ?? [],
                'company_id' => $validated['company_id'] ?? $user->company_id,
                'company_code' => $validated['company_code'] ?? $user->company_code,
                'company_name' => $validated['company_name'] ?? $user->company_name,
            ],
        );

        return response()->json(['session' => $this->sessionPayload($session)]);
    }

    public function members(Request $request, WalkSession $walkSession): JsonResponse
    {
        $user = $this->user($request);
        if (!$this->ownsSession($user, $walkSession)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $members = WalkSessionMember::query()
            ->where('walk_session_id', $walkSession->id)
            ->orderBy('username')
            ->get()
            ->map(fn (WalkSessionMember $member) => $this->memberPayload($member));

        return response()->json(['members' => $members]);
    }

    public function storeMember(Request $request, WalkSession $walkSession): JsonResponse
    {
        $user = $this->user($request);
        if (!$this->ownsSession($user, $walkSession)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'user_id' => ['required', 'string', 'max:255'],
            'username' => ['nullable', 'string', 'max:255'],
            'status' => ['nullable', 'string', 'max:32'],
            'is_tracking' => ['sometimes', 'boolean'],
            'step_count' => ['sometimes', 'integer', 'min:0'],
            'distance_meters' => ['sometimes', 'numeric', 'min:0'],
            'elapsed_seconds' => ['sometimes', 'integer', 'min:0'],
            'route_points' => ['sometimes', 'array'],
            'current_location_lat' => ['nullable', 'numeric'],
            'current_location_lng' => ['nullable', 'numeric'],
        ]);

        $member = WalkSessionMember::updateOrCreate(
            [
                'walk_session_id' => $walkSession->id,
                'user_id' => $validated['user_id'],
            ],
            [
                'id' => (string) Str::uuid(),
                'username' => $validated['username'] ?? null,
                'status' => $validated['status'] ?? 'accepted',
                'is_tracking' => $validated['is_tracking'] ?? false,
                'step_count' => $validated['step_count'] ?? 0,
                'distance_meters' => $validated['distance_meters'] ?? 0,
                'elapsed_seconds' => $validated['elapsed_seconds'] ?? 0,
                'route_points' => $validated['route_points'] ?? [],
                'current_location_lat' => $validated['current_location_lat'] ?? null,
                'current_location_lng' => $validated['current_location_lng'] ?? null,
            ],
        );

        $this->syncSessionParticipants($walkSession, $validated['user_id']);

        return response()->json(['member' => $this->memberPayload($member->refresh())]);
    }

    public function destroyMember(Request $request, WalkSession $walkSession, string $userId): JsonResponse
    {
        $user = $this->user($request);
        if (!$this->ownsSession($user, $walkSession)) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        WalkSessionMember::query()
            ->where('walk_session_id', $walkSession->id)
            ->where('user_id', $userId)
            ->delete();

        $this->syncSessionParticipants($walkSession);

        return response()->json(['message' => 'Deleted.']);
    }

    public function invites(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $invites = WalkInvite::query()
            ->where('to_user_id', (string) $user->id)
            ->orderByDesc('updated_at')
            ->get()
            ->map(fn (WalkInvite $invite) => $this->invitePayload($invite));

        return response()->json(['invites' => $invites]);
    }

    public function storeInvite(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'id' => ['sometimes', 'string', 'max:255'],
            'walk_session_id' => ['required', 'string', 'max:255'],
            'from_user_id' => ['required', 'string', 'max:255'],
            'from_username' => ['nullable', 'string', 'max:255'],
            'to_user_id' => ['required', 'string', 'max:255'],
            'to_username' => ['nullable', 'string', 'max:255'],
        ]);

        $invite = WalkInvite::updateOrCreate(
            [
                'id' => $validated['id'] ?? $validated['walk_session_id'] . ':' . $validated['to_user_id'],
            ],
            [
                'walk_session_id' => $validated['walk_session_id'],
                'from_user_id' => $validated['from_user_id'],
                'from_username' => $validated['from_username'] ?? null,
                'to_user_id' => $validated['to_user_id'],
                'to_username' => $validated['to_username'] ?? null,
                'status' => 'pending',
            ],
        );

        return response()->json(['invite' => $this->invitePayload($invite)]);
    }

    public function updateInvite(Request $request, WalkInvite $walkInvite): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null || (string) $walkInvite->to_user_id !== (string) $user->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'status' => ['required', 'string', 'max:32'],
        ]);

        $walkInvite->update(['status' => strtolower(trim($validated['status']))]);

        if ($walkInvite->status === 'accepted') {
            WalkSessionMember::updateOrCreate(
                [
                    'walk_session_id' => $walkInvite->walk_session_id,
                    'user_id' => $walkInvite->to_user_id,
                ],
                [
                    'id' => (string) Str::uuid(),
                    'username' => $walkInvite->to_username,
                    'status' => 'accepted',
                    'is_tracking' => false,
                    'step_count' => 0,
                    'distance_meters' => 0,
                    'elapsed_seconds' => 0,
                    'route_points' => [],
                ],
            );

            $session = WalkSession::query()->find($walkInvite->walk_session_id);
            if ($session) {
                $session->update(['status' => 'active']);
            }
        }

        return response()->json(['invite' => $this->invitePayload($walkInvite->refresh())]);
    }

    public function recorded(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $walks = RecordedWalk::query()
            ->where('user_id', $user->id)
            ->orderByDesc('ended_at')
            ->get()
            ->map(fn (RecordedWalk $walk) => $this->recordedPayload($walk));

        return response()->json(['walks' => $walks]);
    }

    public function storeRecorded(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'id' => ['required', 'string', 'max:255'],
            'username' => ['nullable', 'string', 'max:255'],
            'started_at' => ['nullable', 'date'],
            'ended_at' => ['nullable', 'date'],
            'step_count' => ['sometimes', 'integer', 'min:0'],
            'distance_meters' => ['sometimes', 'numeric', 'min:0'],
            'elapsed_seconds' => ['sometimes', 'integer', 'min:0'],
            'route_points' => ['sometimes', 'array'],
            'interrupted' => ['sometimes', 'boolean'],
        ]);

        $walk = RecordedWalk::updateOrCreate(
            ['id' => $validated['id']],
            [
                'user_id' => $user->id,
                'username' => $validated['username'] ?? $user->name,
                'started_at' => isset($validated['started_at']) ? Carbon::parse($validated['started_at']) : null,
                'ended_at' => isset($validated['ended_at']) ? Carbon::parse($validated['ended_at']) : null,
                'step_count' => $validated['step_count'] ?? 0,
                'distance_meters' => $validated['distance_meters'] ?? 0,
                'elapsed_seconds' => $validated['elapsed_seconds'] ?? 0,
                'route_points' => $validated['route_points'] ?? [],
                'interrupted' => $validated['interrupted'] ?? false,
            ],
        );

        return response()->json(['walk' => $this->recordedPayload($walk)]);
    }

    public function destroyRecorded(Request $request, RecordedWalk $recordedWalk): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null || (int) $recordedWalk->user_id !== (int) $user->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $recordedWalk->delete();

        return response()->json(['message' => 'Deleted.']);
    }

    public function inviteCandidates(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
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
            ->map(fn (User $candidate) => [
                'id' => (string) $candidate->id,
                'username' => $candidate->name,
                'email' => $candidate->email,
                'profilePic' => $candidate->profile_pic,
                'companyName' => $candidate->company_name,
                'companyCode' => $candidate->company_code,
            ])
            ->values();

        return response()->json(['users' => $users]);
    }

    private function activeCompanyValue(?string $primary, ?string $fallback): string
    {
        $value = trim((string) ($primary ?? ''));
        if ($value !== '') {
            return $value;
        }
        return trim((string) ($fallback ?? ''));
    }

    private function user(Request $request): ?User
    {
        $user = $request->user();
        return $user instanceof User ? $user : null;
    }

    private function ownsSession(?User $user, WalkSession $session): bool
    {
        if ($user === null) return false;
        return in_array((string) $user->id, array_map('strval', $session->participant_ids ?? []), true)
            || (string) $session->created_by === (string) $user->id;
    }

    private function syncSessionParticipants(WalkSession $session, ?string $newUserId = null): void
    {
        $ids = WalkSessionMember::query()
            ->where('walk_session_id', $session->id)
            ->pluck('user_id')
            ->map(fn ($id) => (string) $id)
            ->values()
            ->all();

        if ($newUserId !== null && ! in_array($newUserId, $ids, true)) {
            $ids[] = $newUserId;
        }

        $session->update(['participant_ids' => array_values(array_unique($ids))]);
    }

    private function sessionPayload(WalkSession $session): array
    {
        return [
            'id' => (string) $session->id,
            'createdBy' => $session->created_by,
            'createdByName' => $session->created_by_name,
            'status' => $session->status,
            'participantIds' => $session->participant_ids ?? [],
            'companyId' => $session->company_id,
            'companyCode' => $session->company_code,
            'companyName' => $session->company_name,
            'updatedAt' => $session->updated_at?->toIso8601String(),
        ];
    }

    private function memberPayload(WalkSessionMember $member): array
    {
        return [
            'userId' => (string) $member->user_id,
            'username' => $member->username,
            'status' => $member->status,
            'isTracking' => (bool) $member->is_tracking,
            'stepCount' => (int) $member->step_count,
            'distanceMeters' => (float) $member->distance_meters,
            'elapsedSeconds' => (int) $member->elapsed_seconds,
            'routePoints' => $member->route_points ?? [],
            'currentLocation' => $member->current_location_lat !== null && $member->current_location_lng !== null
                ? ['latitude' => (float) $member->current_location_lat, 'longitude' => (float) $member->current_location_lng]
                : null,
            'updatedAt' => $member->updated_at?->toIso8601String(),
        ];
    }

    private function invitePayload(WalkInvite $invite): array
    {
        return [
            'id' => (string) $invite->id,
            'sessionId' => (string) $invite->walk_session_id,
            'fromUserId' => (string) $invite->from_user_id,
            'fromUsername' => $invite->from_username,
            'toUserId' => (string) $invite->to_user_id,
            'toUsername' => $invite->to_username,
            'status' => $invite->status,
            'createdAt' => $invite->created_at?->toIso8601String(),
            'updatedAt' => $invite->updated_at?->toIso8601String(),
        ];
    }

    private function recordedPayload(RecordedWalk $walk): array
    {
        return [
            'id' => (string) $walk->id,
            'userId' => (string) $walk->user_id,
            'username' => $walk->username,
            'startedAt' => $walk->started_at?->toIso8601String(),
            'endedAt' => $walk->ended_at?->toIso8601String(),
            'stepCount' => (int) $walk->step_count,
            'distanceMeters' => (float) $walk->distance_meters,
            'elapsedSeconds' => (int) $walk->elapsed_seconds,
            'routePoints' => $walk->route_points ?? [],
            'interrupted' => (bool) $walk->interrupted,
        ];
    }
}
