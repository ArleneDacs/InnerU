<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\Response;

class AdminUserController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $admin = $request->user();
        if ($admin === null || ! $this->isAdmin($admin)) {
            return response()->json([
                'message' => 'Unauthorized.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $users = User::query()
            ->orderBy('name')
            ->get()
            ->map(fn (User $user) => $this->userPayload($user));

        return response()->json([
            'users' => $users,
        ]);
    }

    public function updateRole(Request $request, User $user): JsonResponse
    {
        $admin = $request->user();
        if ($admin === null || ! $this->isAdmin($admin)) {
            return response()->json([
                'message' => 'Unauthorized.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'role' => ['required', 'string', Rule::in(['user', 'coach', 'admin'])],
            'name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'number' => ['sometimes', 'nullable', 'string', 'max:30'],
        ]);

        $role = strtolower(trim($validated['role']));
        $user->role = $role;
        $user->is_coach = $role === 'coach';
        $user->is_admin = $role === 'admin';

        if (array_key_exists('name', $validated) && $validated['name'] !== null) {
            $user->name = trim($validated['name']);
        }
        if (array_key_exists('number', $validated)) {
            $user->number = trim((string) ($validated['number'] ?? '')) ?: null;
        }

        $user->save();

        return response()->json([
            'user' => $this->userPayload($user->refresh()),
        ]);
    }

    private function isAdmin(User $user): bool
    {
        $role = strtolower(trim((string) $user->role));
        return $role === 'admin' || (bool) $user->is_admin;
    }

    private function userPayload(User $user): array
    {
        return [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'number' => $user->number,
            'role' => $user->role,
            'isCoach' => (bool) $user->is_coach,
            'isAdmin' => (bool) $user->is_admin,
            'companyName' => $user->company_name,
            'companyCode' => $user->company_code,
            'profilePic' => $user->profile_pic,
            'createdAt' => optional($user->created_at)?->toIso8601String(),
            'updatedAt' => optional($user->updated_at)?->toIso8601String(),
        ];
    }
}
