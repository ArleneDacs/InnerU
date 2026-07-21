<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Password;
use Illuminate\Validation\Rules\Password as PasswordRule;
use Symfony\Component\HttpFoundation\Response;

class AuthController extends Controller
{
    public function register(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'string', 'email:rfc,dns', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', PasswordRule::min(8)],
            'number' => ['nullable', 'string', 'max:30'],
            'role' => ['required', 'string', 'max:30'],
            'company_code' => ['nullable', 'string', 'max:60'],
            'company_name' => ['nullable', 'string', 'max:120'],
        ]);

        $user = User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'number' => $validated['number'] ?? null,
            'role' => $validated['role'],
            'is_coach' => strtolower($validated['role']) === 'coach',
            'company_code' => $validated['company_code'] ?? null,
            'company_name' => $validated['company_name'] ?? null,
            'has_company' => filled($validated['company_code'] ?? null),
            'company_id' => $validated['company_code'] ?? null,
            'active_company_id' => $validated['company_code'] ?? null,
            'active_company_code' => $validated['company_code'] ?? null,
            'active_company_name' => $validated['company_name'] ?? null,
            'active_company_score_mode' => null,
            'score_mode' => null,
            'company_memberships' => null,
            'company_ids' => null,
            'company_codes' => null,
            'daily_step_goal' => null,
            'daily_tracker_items' => null,
            'password' => Hash::make($validated['password']),
        ]);

        $token = $user->createToken('mobile')->plainTextToken;

        return response()->json([
            'token_type' => 'Bearer',
            'token' => $token,
            'user' => $this->userPayload($user),
        ], Response::HTTP_CREATED);
    }

    public function login(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email:rfc,dns'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('email', $validated['email'])->first();

        if (! $user || ! Hash::check($validated['password'], $user->password)) {
            return response()->json([
                'message' => 'The provided credentials are incorrect.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $user->tokens()->delete();
        $token = $user->createToken('mobile')->plainTextToken;

        return response()->json([
            'token_type' => 'Bearer',
            'token' => $token,
            'user' => $this->userPayload($user),
        ]);
    }

    public function sendPasswordResetLink(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'email' => ['required', 'string', 'email:rfc,dns', 'max:255'],
        ]);

        $status = Password::broker()->sendResetLink($validated);

        if ($status !== Password::RESET_LINK_SENT) {
            return response()->json([
                'message' => __($status),
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        return response()->json([
            'message' => 'Password reset link sent.',
        ]);
    }

    public function resetPassword(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'token' => ['required', 'string'],
            'email' => ['required', 'string', 'email:rfc,dns', 'max:255'],
            'password' => ['required', 'string', PasswordRule::min(8), 'confirmed'],
        ]);

        $status = Password::reset(
            $validated,
            function (User $user, string $password): void {
                $user->forceFill([
                    'password' => Hash::make($password),
                ])->save();
            }
        );

        if ($status !== Password::PASSWORD_RESET) {
            return response()->json([
                'message' => __($status),
            ], Response::HTTP_UNPROCESSABLE_ENTITY);
        }

        return response()->json([
            'message' => 'Password updated successfully.',
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()?->currentAccessToken()?->delete();

        return response()->json([
            'message' => 'Logged out successfully.',
        ]);
    }

    public function destroy(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user === null) {
            return response()->json([
                'message' => 'No authenticated user found.',
            ], Response::HTTP_UNAUTHORIZED);
        }

        $user->tokens()->delete();
        $user->delete();

        return response()->json([
            'message' => 'Account deleted successfully.',
        ]);
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
            'dailyTrackerItems' => $user->daily_tracker_items ?? [],
            'birthdate' => optional($user->birthdate)?->format('Y-m-d'),
            'profile_pic' => $user->profile_pic,
            'created_at' => optional($user->created_at)?->toIso8601String(),
            'updated_at' => optional($user->updated_at)?->toIso8601String(),
        ];
    }

}
