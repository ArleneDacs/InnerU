<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DailyCheckIn;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Symfony\Component\HttpFoundation\Response;

class DailyCheckInController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $date = $request->string('date')->trim()->value() ?: now()->toDateString();
        $checkIn = DailyCheckIn::query()
            ->where('user_id', $user->id)
            ->whereDate('date', $date)
            ->latest('updated_at')
            ->first();

        return response()->json([
            'checkIn' => $checkIn ? $this->mapCheckIn($checkIn) : null,
        ]);
    }

    public function history(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'month' => ['nullable', 'date_format:Y-m'],
        ]);

        $month = $validated['month'] ?? now()->format('Y-m');
        $parsed = Carbon::createFromFormat('Y-m', $month);

        $checkIns = DailyCheckIn::query()
            ->where('user_id', $user->id)
            ->whereYear('date', $parsed->year)
            ->whereMonth('date', $parsed->month)
            ->orderBy('date')
            ->get()
            ->map(fn (DailyCheckIn $checkIn) => $this->mapCheckIn($checkIn))
            ->values();

        return response()->json([
            'checkIns' => $checkIns,
        ]);
    }

    public function upsert(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'date' => ['nullable', 'date'],
            'rating' => ['required', 'integer', 'min:1', 'max:5'],
            'wins_today' => ['nullable', 'string', 'max:2000'],
            'challenges' => ['nullable', 'string', 'max:2000'],
            'lessons_learned' => ['nullable', 'string', 'max:2000'],
            'gratitude' => ['nullable', 'string', 'max:2000'],
            'tomorrow_focus' => ['nullable', 'string', 'max:2000'],
            'username' => ['nullable', 'string', 'max:120'],
            'last_filed_at' => ['nullable', 'date'],
        ]);

        $date = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : now()->toDateString();

        $checkIn = DailyCheckIn::updateOrCreate(
            [
                'user_id' => $user->id,
                'date' => $date,
            ],
            [
                'username' => $validated['username'] ?? $user->name,
                'rating' => $validated['rating'],
                'wins_today' => $validated['wins_today'] ?? '',
                'challenges' => $validated['challenges'] ?? '',
                'lessons_learned' => $validated['lessons_learned'] ?? '',
                'gratitude' => $validated['gratitude'] ?? '',
                'tomorrow_focus' => $validated['tomorrow_focus'] ?? '',
                'last_filed_at' => $validated['last_filed_at'] ?? now(),
            ]
        );

        return response()->json([
            'checkIn' => $this->mapCheckIn($checkIn),
        ]);
    }

    private function mapCheckIn(DailyCheckIn $checkIn): array
    {
        return [
            'id' => (string) $checkIn->id,
            'userId' => (string) $checkIn->user_id,
            'username' => $checkIn->username,
            'date' => $checkIn->date?->toDateString(),
            'rating' => $checkIn->rating,
            'winsToday' => $checkIn->wins_today,
            'challenges' => $checkIn->challenges,
            'lessonsLearned' => $checkIn->lessons_learned,
            'gratitude' => $checkIn->gratitude,
            'tomorrowFocus' => $checkIn->tomorrow_focus,
            'lastFiledAt' => $checkIn->last_filed_at?->toIso8601String(),
            'createdAt' => $checkIn->created_at?->toIso8601String(),
            'updatedAt' => $checkIn->updated_at?->toIso8601String(),
        ];
    }
}
