<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Emotion;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Symfony\Component\HttpFoundation\Response;

class EmotionController extends Controller
{
    public function today(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $date = $request->string('date')->trim()->value() ?: now()->toDateString();
        $emotion = Emotion::query()
            ->where('user_id', $user->id)
            ->whereDate('date', $date)
            ->latest('updated_at')
            ->first();

        return response()->json([
            'emotion' => $emotion?->emotion,
            'record' => $emotion ? $this->mapEmotion($emotion) : null,
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

        $emotions = Emotion::query()
            ->where('user_id', $user->id)
            ->whereYear('date', $parsed->year)
            ->whereMonth('date', $parsed->month)
            ->orderBy('date')
            ->get()
            ->map(fn (Emotion $emotion) => $this->mapEmotion($emotion))
            ->values();

        return response()->json([
            'emotions' => $emotions,
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'emotion' => ['required', 'string', 'max:80'],
            'username' => ['nullable', 'string', 'max:120'],
            'date' => ['nullable', 'date'],
            'history' => ['nullable', 'array'],
            'logged_at' => ['nullable', 'date'],
        ]);

        $date = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : now()->toDateString();

        $record = Emotion::updateOrCreate(
            [
                'user_id' => $user->id,
                'date' => $date,
            ],
            [
                'username' => $validated['username'] ?? $user->name,
                'emotion' => $validated['emotion'],
                'history' => $validated['history'] ?? [],
                'last_logged_at' => $validated['logged_at'] ?? now(),
            ]
        );

        return response()->json([
            'record' => $this->mapEmotion($record),
        ]);
    }

    private function mapEmotion(Emotion $emotion): array
    {
        return [
            'id' => (string) $emotion->id,
            'userId' => (string) $emotion->user_id,
            'username' => $emotion->username,
            'emotion' => $emotion->emotion,
            'date' => $emotion->date?->toDateString(),
            'history' => $emotion->history ?? [],
            'lastLoggedAt' => $emotion->last_logged_at?->toIso8601String(),
            'createdAt' => $emotion->created_at?->toIso8601String(),
            'updatedAt' => $emotion->updated_at?->toIso8601String(),
        ];
    }
}
