<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
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
            'due_date' => ['required', 'date'],
            'tag' => ['nullable', 'string', 'max:64'],
            'is_completed' => ['sometimes', 'boolean'],
            'completed_at' => ['nullable', 'date'],
            'sub_tasks' => ['nullable', 'array'],
        ]);

        $task = TodoTask::updateOrCreate(
            [
                'id' => $validated['id'] ?? (string) Str::uuid(),
                'user_id' => $user->id,
            ],
            [
                'title' => $validated['title'],
                'description' => $validated['description'] ?? '',
                'due_date' => Carbon::parse($validated['due_date'])->toDateString(),
                'tag' => $validated['tag'] ?? 'none',
                'is_completed' => $validated['is_completed'] ?? false,
                'completed_at' => isset($validated['completed_at'])
                    ? Carbon::parse($validated['completed_at'])
                    : null,
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
            'due_date' => ['sometimes', 'date'],
            'tag' => ['nullable', 'string', 'max:64'],
            'is_completed' => ['sometimes', 'boolean'],
            'completed_at' => ['nullable', 'date'],
            'sub_tasks' => ['nullable', 'array'],
        ]);

        if (array_key_exists('title', $validated)) {
            $todoTask->title = $validated['title'];
        }
        if (array_key_exists('description', $validated)) {
            $todoTask->description = $validated['description'];
        }
        if (array_key_exists('due_date', $validated)) {
            $todoTask->due_date = Carbon::parse($validated['due_date'])->toDateString();
        }
        if (array_key_exists('tag', $validated)) {
            $todoTask->tag = $validated['tag'];
        }
        if (array_key_exists('is_completed', $validated)) {
            $todoTask->is_completed = (bool) $validated['is_completed'];
        }
        if (array_key_exists('completed_at', $validated)) {
            $todoTask->completed_at = $validated['completed_at'] === null
                ? null
                : Carbon::parse($validated['completed_at']);
        }
        if (array_key_exists('sub_tasks', $validated)) {
            $todoTask->sub_tasks = $validated['sub_tasks'];
        }

        $todoTask->save();

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
            'isCompleted' => (bool) $task->is_completed,
            'dueDate' => $task->due_date?->toDateString(),
            'tag' => $task->tag,
            'createdAt' => $task->created_at?->toIso8601String(),
            'updatedAt' => $task->updated_at?->toIso8601String(),
            'completedAt' => $task->completed_at?->toIso8601String(),
            'subTasks' => $task->sub_tasks ?? [],
        ];
    }
}
