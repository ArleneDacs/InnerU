<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DashboardController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], 401);
        }

        return response()->json([
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'number' => $user->number,
                'role' => $user->role,
                'is_coach' => (bool) $user->is_coach,
                'company_code' => $user->company_code,
                'company_name' => $user->company_name,
                'profile_pic' => $user->profile_pic,
                'score' => (int) $user->score,
            ],
            'summary' => [
                'score' => (int) $user->score,
                'company_name' => $user->company_name,
                'company_code' => $user->company_code,
                'today_emotion' => null,
                'quote' => 'Small steps count.',
                'author' => 'InnerU',
            ],
        ]);
    }
}
