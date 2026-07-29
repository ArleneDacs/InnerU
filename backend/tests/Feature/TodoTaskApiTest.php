<?php

namespace Tests\Feature;

use App\Models\TodoTask;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class TodoTaskApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_task_creation_persists_start_and_due_dates(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/todo-tasks', [
            'title' => 'Plan the launch',
            'description' => 'Start strong and finish by the deadline.',
            'start_date' => '2026-07-01',
            'due_date' => '2026-09-01',
            'tag' => 'personal',
            'sub_tasks' => [],
        ]);

        $response->assertCreated()
            ->assertJsonPath('task.startDate', '2026-07-01')
            ->assertJsonPath('task.dueDate', '2026-09-01');

        $taskId = $response->json('task.id');
        $this->assertDatabaseHas('todo_tasks', [
            'id' => $taskId,
            'user_id' => $user->id,
        ]);

        $task = TodoTask::query()->findOrFail($taskId);
        $this->assertSame('2026-07-01', $task->start_date?->toDateString());
        $this->assertSame('2026-09-01', $task->due_date?->toDateString());
        $this->assertSame('LONG_TERM', $task->goal_type);
        $this->assertSame([], $task->completion_dates ?? []);
    }

    public function test_everyday_goal_persists_completion_dates(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $response = $this->postJson('/api/todo-tasks', [
            'title' => 'Do the thing today',
            'description' => 'Check the calendar every day.',
            'goal_type' => 'EVERYDAY',
            'start_date' => '2026-07-01',
            'due_date' => '2026-07-03',
            'tag' => 'personal',
            'completion_dates' => [
                '2026-07-01',
                '2026-07-02T14:00:00+08:00',
                '2026-07-02',
            ],
            'sub_tasks' => [],
        ]);

        $response->assertCreated()
            ->assertJsonPath('task.goalType', 'EVERYDAY')
            ->assertJsonPath('task.completionDates.0', '2026-07-01')
            ->assertJsonPath('task.completionDates.1', '2026-07-02');

        $taskId = $response->json('task.id');
        $task = TodoTask::query()->findOrFail($taskId);

        $this->assertSame('EVERYDAY', $task->goal_type);
        $this->assertSame(
            ['2026-07-01', '2026-07-02'],
            array_values($task->completion_dates ?? [])
        );
    }
}
