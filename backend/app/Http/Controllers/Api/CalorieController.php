<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CalorieDay;
use App\Models\CalorieEntry;
use App\Models\FoodMemory;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

class CalorieController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'date' => ['nullable', 'date'],
        ]);

        $date = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : now()->toDateString();

        $day = $this->dayQuery($user->id, $date)->first();

        return response()->json([
            'day' => $day ? $this->dayPayload($day) : null,
            'entries' => $this->entriesForDay($user->id, $date),
        ]);
    }

    public function history(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'limit' => ['nullable', 'integer', 'min:1', 'max:365'],
        ]);

        $limit = (int) ($validated['limit'] ?? 90);

        return response()->json([
            'days' => $this->dayQuery($user->id)
                ->limit($limit)
                ->get()
                ->map(fn (CalorieDay $day) => $this->dayPayload($day)),
        ]);
    }

    public function upsertDay(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'date' => ['nullable', 'date'],
            'daily_goal' => ['nullable', 'integer', 'min:1', 'max:10000'],
            'water_glasses' => ['nullable', 'integer', 'min:0', 'max:100'],
            'water_goal' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);

        $date = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : now()->toDateString();

        $day = DB::transaction(function () use ($user, $date, $validated): CalorieDay {
            $existing = $this->dayQuery($user->id, $date)->first();
            $totals = $this->totalsForDay($user->id, $date);

            $day = CalorieDay::updateOrCreate(
                [
                    'user_id' => $user->id,
                    'date' => $date,
                ],
                [
                    'daily_goal' => $validated['daily_goal'] ?? $existing?->daily_goal ?? 2000,
                    'total_calories' => $totals['total_calories'],
                    'total_protein' => $totals['total_protein'],
                    'total_carbs' => $totals['total_carbs'],
                    'total_fat' => $totals['total_fat'],
                    'meal_count' => $totals['meal_count'],
                    'water_glasses' => $validated['water_glasses'] ?? $existing?->water_glasses ?? 0,
                    'water_goal' => $validated['water_goal'] ?? $existing?->water_goal ?? 8,
                ]
            );

            return $day->refresh();
        });

        return response()->json([
            'day' => $this->dayPayload($day),
        ]);
    }

    public function storeEntry(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'date' => ['nullable', 'date'],
            'meal' => ['required', 'string', 'max:255'],
            'meal_type' => ['required', 'string', 'max:120'],
            'calories' => ['required', 'integer', 'min:1', 'max:100000'],
            'protein' => ['nullable', 'integer', 'min:0', 'max:100000'],
            'carbs' => ['nullable', 'integer', 'min:0', 'max:100000'],
            'fat' => ['nullable', 'integer', 'min:0', 'max:100000'],
            'quantity' => ['nullable', 'numeric', 'min:0'],
            'measurement_unit' => ['nullable', 'string', 'max:50'],
            'photo_url' => ['nullable', 'string', 'max:2048'],
        ]);

        $date = isset($validated['date'])
            ? Carbon::parse($validated['date'])->toDateString()
            : now()->toDateString();

        $payload = DB::transaction(function () use ($user, $date, $validated): array {
            $day = CalorieDay::query()
                ->firstOrCreate([
                    'user_id' => $user->id,
                    'date' => $date,
                ], [
                    'daily_goal' => 2000,
                    'water_glasses' => 0,
                    'water_goal' => 8,
                ]);

            $entry = CalorieEntry::create([
                'user_id' => $user->id,
                'calorie_day_id' => $day->id,
                'date' => $date,
                'meal' => trim($validated['meal']),
                'meal_type' => trim($validated['meal_type']),
                'calories' => $validated['calories'],
                'protein' => $validated['protein'] ?? 0,
                'carbs' => $validated['carbs'] ?? 0,
                'fat' => $validated['fat'] ?? 0,
                'quantity' => $validated['quantity'] ?? null,
                'measurement_unit' => $validated['measurement_unit'] ?? null,
                'photo_url' => $validated['photo_url'] ?? null,
            ]);

            $totals = $this->totalsForDay($user->id, $date);
            $day->forceFill($totals + [
                'daily_goal' => $day->daily_goal ?: 2000,
                'water_glasses' => $day->water_glasses ?: 0,
                'water_goal' => $day->water_goal ?: 8,
            ])->save();

            return [
                'entry' => $this->entryPayload($entry),
                'day' => $this->dayPayload($day->refresh()),
                'entries' => $this->entriesForDay($user->id, $date),
            ];
        });

        return response()->json($payload, Response::HTTP_CREATED);
    }

    public function showFoodMemory(Request $request, string $key): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $memory = FoodMemory::query()
            ->where('user_id', $user->id)
            ->where('key', $key)
            ->first();

        return response()->json([
            'memory' => $memory ? $this->foodMemoryPayload($memory) : null,
        ]);
    }

    public function upsertFoodMemory(Request $request): JsonResponse
    {
        $user = $request->user();
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'key' => ['required', 'string', 'max:120'],
            'display_name' => ['required', 'string', 'max:255'],
            'lookup_name' => ['required', 'string', 'max:255'],
            'calories' => ['required', 'integer', 'min:1', 'max:100000'],
            'protein' => ['nullable', 'integer', 'min:0', 'max:100000'],
            'carbs' => ['nullable', 'integer', 'min:0', 'max:100000'],
            'fat' => ['nullable', 'integer', 'min:0', 'max:100000'],
            'source' => ['nullable', 'string', 'max:120'],
        ]);

        $memory = FoodMemory::updateOrCreate(
            [
                'user_id' => $user->id,
                'key' => trim($validated['key']),
            ],
            [
                'display_name' => trim($validated['display_name']),
                'lookup_name' => trim($validated['lookup_name']),
                'calories' => $validated['calories'],
                'protein' => $validated['protein'] ?? 0,
                'carbs' => $validated['carbs'] ?? 0,
                'fat' => $validated['fat'] ?? 0,
                'source' => trim((string) ($validated['source'] ?? 'manual')),
            ]
        );

        return response()->json([
            'memory' => $this->foodMemoryPayload($memory),
        ]);
    }

    private function dayQuery(int|string $userId, ?string $date = null)
    {
        $query = CalorieDay::query()
            ->where('user_id', $userId);

        if ($date !== null) {
            $query->whereDate('date', $date);
        }

        return $query->orderByDesc('date')->orderByDesc('id');
    }

    private function entriesForDay(int|string $userId, string $date)
    {
        return CalorieEntry::query()
            ->where('user_id', $userId)
            ->whereDate('date', $date)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn (CalorieEntry $entry) => $this->entryPayload($entry));
    }

    private function totalsForDay(int|string $userId, string $date): array
    {
        $entries = CalorieEntry::query()
            ->where('user_id', $userId)
            ->whereDate('date', $date)
            ->get();

        return [
            'total_calories' => $entries->sum('calories'),
            'total_protein' => $entries->sum('protein'),
            'total_carbs' => $entries->sum('carbs'),
            'total_fat' => $entries->sum('fat'),
            'meal_count' => $entries->count(),
        ];
    }

    private function dayPayload(CalorieDay $day): array
    {
        return [
            'id' => (string) $day->id,
            'userId' => (string) $day->user_id,
            'date' => $day->date?->toDateString(),
            'dailyGoal' => $day->daily_goal,
            'totalCalories' => $day->total_calories,
            'totalProtein' => $day->total_protein,
            'totalCarbs' => $day->total_carbs,
            'totalFat' => $day->total_fat,
            'mealCount' => $day->meal_count,
            'waterGlasses' => $day->water_glasses,
            'waterGoal' => $day->water_goal,
            'createdAt' => $day->created_at?->toIso8601String(),
            'updatedAt' => $day->updated_at?->toIso8601String(),
        ];
    }

    private function entryPayload(CalorieEntry $entry): array
    {
        return [
            'id' => (string) $entry->id,
            'meal' => $entry->meal,
            'mealType' => $entry->meal_type,
            'calories' => $entry->calories,
            'protein' => $entry->protein,
            'carbs' => $entry->carbs,
            'fat' => $entry->fat,
            'quantity' => $entry->quantity,
            'measurementUnit' => $entry->measurement_unit,
            'photoUrl' => $entry->photo_url,
            'createdAt' => $entry->created_at?->toIso8601String(),
        ];
    }

    private function foodMemoryPayload(FoodMemory $memory): array
    {
        return [
            'id' => (string) $memory->id,
            'key' => $memory->key,
            'displayName' => $memory->display_name,
            'lookupName' => $memory->lookup_name,
            'calories' => $memory->calories,
            'protein' => $memory->protein,
            'carbs' => $memory->carbs,
            'fat' => $memory->fat,
            'source' => $memory->source,
            'createdAt' => $memory->created_at?->toIso8601String(),
            'updatedAt' => $memory->updated_at?->toIso8601String(),
        ];
    }
}
