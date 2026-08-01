<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CoachMentee;
use App\Models\Notification;
use App\Models\TodoTask;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

class TodoTaskController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $tasks = TodoTask::query()
            ->where('user_id', $user->id)
            ->orderByRaw('COALESCE(due_date, created_at) asc')
            ->orderBy('created_at')
            ->get()
            ->map(fn (TodoTask $task) => $this->payload($task));

        return response()->json(['tasks' => $tasks]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'id' => ['sometimes', 'string', 'max:255'],
            'title' => ['required', 'string', 'max:255'],
            'description' => ['nullable', 'string'],
            'goal_type' => ['nullable', 'string', 'max:32'],
            'start_date' => ['nullable', 'date'],
            'due_date' => ['required', 'date'],
            'tag' => ['nullable', 'string', 'max:64'],
            'tag_index' => ['nullable', 'integer', 'min:0', 'max:3'],
            'is_completed' => ['sometimes', 'boolean'],
            'completed_at' => ['nullable', 'date'],
            'completion_dates' => ['nullable', 'array'],
            'sub_tasks' => ['nullable', 'array'],
        ]);

        $goalType = $this->normalizeGoalType($validated['goal_type'] ?? null);
        $startDate = isset($validated['start_date'])
            ? Carbon::parse($validated['start_date'])->startOfDay()
            : Carbon::parse($validated['due_date'])->startOfDay();
        $dueDate = Carbon::parse($validated['due_date'])->startOfDay();
        $dueDate = $this->normalizeLongTermRange($goalType, $startDate, $dueDate);

        $task = TodoTask::updateOrCreate(
            [
                'id' => $validated['id'] ?? (string) Str::uuid(),
                'user_id' => $user->id,
            ],
            [
                'title' => $validated['title'],
                'description' => $validated['description'] ?? '',
                'goal_type' => $goalType,
                'start_date' => $startDate->toDateString(),
                'due_date' => $dueDate?->toDateString() ?? $startDate->addDay()->toDateString(),
                'tag' => $this->normalizeTag(
                    $validated['tag'] ?? null,
                    $validated['tag_index'] ?? null,
                ),
                'is_completed' => $validated['is_completed'] ?? false,
                'completed_at' => isset($validated['completed_at'])
                    ? Carbon::parse($validated['completed_at'])
                    : null,
                'completion_dates' => $this->normalizeCompletionDates(
                    $validated['completion_dates'] ?? []
                ),
                'sub_tasks' => $validated['sub_tasks'] ?? [],
            ],
        );

        return response()->json(['task' => $this->payload($task)], Response::HTTP_CREATED);
    }

    public function update(Request $request, TodoTask $todoTask): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null || (int) $todoTask->user_id !== (int) $user->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $validated = $request->validate([
            'title' => ['sometimes', 'string', 'max:255'],
            'description' => ['nullable', 'string'],
            'goal_type' => ['sometimes', 'nullable', 'string', 'max:32'],
            'start_date' => ['sometimes', 'date'],
            'due_date' => ['sometimes', 'date'],
            'tag' => ['nullable', 'string', 'max:64'],
            'tag_index' => ['nullable', 'integer', 'min:0', 'max:3'],
            'is_completed' => ['sometimes', 'boolean'],
            'completed_at' => ['nullable', 'date'],
            'completion_dates' => ['sometimes', 'nullable', 'array'],
            'sub_tasks' => ['nullable', 'array'],
        ]);

        $wasCompleted = (bool) $todoTask->is_completed;

        if (array_key_exists('title', $validated)) {
            $todoTask->title = $validated['title'];
        }
        if (array_key_exists('description', $validated)) {
            $todoTask->description = $validated['description'];
        }
        if (array_key_exists('goal_type', $validated)) {
            $todoTask->goal_type = $this->normalizeGoalType($validated['goal_type']);
        }
        if (array_key_exists('start_date', $validated)) {
            $todoTask->start_date = Carbon::parse($validated['start_date'])->toDateString();
        }
        if (array_key_exists('due_date', $validated)) {
            $todoTask->due_date = Carbon::parse($validated['due_date'])->toDateString();
        }
        if (array_key_exists('tag', $validated)) {
            $todoTask->tag = $this->normalizeTag(
                $validated['tag'] ?? null,
                $validated['tag_index'] ?? null,
            );
        } elseif (array_key_exists('tag_index', $validated)) {
            $todoTask->tag = $this->tagFromIndex((int) $validated['tag_index']);
        }
        if (array_key_exists('is_completed', $validated)) {
            $todoTask->is_completed = (bool) $validated['is_completed'];
        }
        if (array_key_exists('completed_at', $validated)) {
            $todoTask->completed_at = $validated['completed_at'] === null
                ? null
                : Carbon::parse($validated['completed_at']);
        }
        if (array_key_exists('completion_dates', $validated)) {
            $todoTask->completion_dates = $this->normalizeCompletionDates(
                $validated['completion_dates']
            );
        }
        if (array_key_exists('sub_tasks', $validated)) {
            $todoTask->sub_tasks = $validated['sub_tasks'];
        }

        if (
            $todoTask->goal_type === 'LONG_TERM'
            && $todoTask->start_date !== null
            && $todoTask->due_date !== null
            && $todoTask->due_date->startOfDay()->lte($todoTask->start_date->startOfDay())
        ) {
            $todoTask->due_date = $todoTask->start_date->copy()->addDay()->startOfDay();
        }

        $todoTask->save();

        // Throttled: only on the NOT completed -> completed transition, not
        // on every other edit and not when un-completing.
        if (! $wasCompleted && $todoTask->is_completed) {
            foreach (CoachMentee::coachIdsForMentee((string) $user->id) as $coachId) {
                Notification::createFor(
                    $coachId,
                    'mentee_progress_logged',
                    sprintf('%s completed a todo task', $user->name),
                    $todoTask->title,
                    [
                        'menteeId' => (string) $user->id,
                        'todoTaskId' => (string) $todoTask->id,
                    ],
                );
            }
        }

        return response()->json(['task' => $this->payload($todoTask->refresh())]);
    }

    public function destroy(Request $request, TodoTask $todoTask): JsonResponse
    {
        $user = $this->user($request);
        if ($user === null || (int) $todoTask->user_id !== (int) $user->id) {
            return response()->json(['message' => 'Unauthorized.'], Response::HTTP_UNAUTHORIZED);
        }

        $todoTask->delete();

        return response()->json(['message' => 'Deleted.']);
    }

    private function user(Request $request): ?User
    {
        $user = $request->user();
        return $user instanceof User ? $user : null;
    }

    private function payload(TodoTask $task): array
    {
        return [
            'id' => (string) $task->id,
            'title' => $task->title,
            'description' => $task->description,
            'goalType' => $task->goal_type,
            'isCompleted' => (bool) $task->is_completed,
            'startDate' => $task->start_date?->toDateString(),
            'dueDate' => $task->due_date?->toDateString(),
            'tag' => $task->tag,
            'tagIndex' => $this->tagIndexFromValue($task->tag),
            'createdAt' => $task->created_at?->toIso8601String(),
            'updatedAt' => $task->updated_at?->toIso8601String(),
            'completedAt' => $task->completed_at?->toIso8601String(),
            'completionDates' => collect($task->completion_dates ?? [])
                ->map(fn ($date) => Carbon::parse($date)->toDateString())
                ->values()
                ->all(),
            'subTasks' => $task->sub_tasks ?? [],
        ];
    }

    private function normalizeGoalType(?string $goalType): string
    {
        $normalized = strtoupper(trim((string) $goalType));
        return match ($normalized) {
            'EVERYDAY', 'DAILY' => 'EVERYDAY',
            default => 'LONG_TERM',
        };
    }

    private function normalizeLongTermRange(string $goalType, ?Carbon $startDate, ?Carbon $dueDate): ?Carbon
    {
        if ($goalType !== 'LONG_TERM' || $startDate === null || $dueDate === null) {
            return $dueDate;
        }

        if ($dueDate->startOfDay()->lte($startDate->startOfDay())) {
            return $startDate->copy()->addDay()->startOfDay();
        }

        return $dueDate;
    }

    /**
     * @param  array<int, mixed>  $completionDates
     * @return array<int, string>
     */
    private function normalizeCompletionDates(array $completionDates): array
    {
        return collect($completionDates)
            ->map(fn ($date) => Carbon::parse($date)->toDateString())
            ->unique()
            ->values()
            ->all();
    }

    private function normalizeTag(?string $tag, ?int $tagIndex): string
    {
        $normalizedTag = strtolower(trim((string) $tag));
        if ($normalizedTag !== '') {
            $index = $this->tagIndexFromValue($normalizedTag);
            if ($index !== null) {
                return $this->tagFromIndex($index);
            }
        }

        if ($tagIndex !== null) {
            return $this->tagFromIndex($tagIndex);
        }

        return 'none';
    }

    private function tagFromIndex(int $tagIndex): string
    {
        return match (max(0, min(3, $tagIndex))) {
            0 => 'personal',
            1 => 'professional',
            2 => 'contribution',
            default => 'none',
        };
    }

    private function tagIndexFromValue(?string $tag): ?int
    {
        $normalized = strtolower(trim((string) $tag));
        $normalized = preg_replace('/[\s_\-]+/', '', $normalized) ?? $normalized;

        return match ($normalized) {
            'personal', 'personalgoals' => 0,
            'professional', 'professionalmilestones', 'professionalgoals' => 1,
            'contribution', 'contributiongoals' => 2,
            'none', 'notag', '' => 3,
            default => null,
        };
    }
}
