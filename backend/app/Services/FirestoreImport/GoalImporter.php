<?php
// backend/app/Services/FirestoreImport/GoalImporter.php

namespace App\Services\FirestoreImport;

use App\Models\Goal;
use App\Models\GoalComment;
use App\Models\GoalMerit;
use App\Models\GoalTask;
use App\Models\GoalUpdate;
use App\Models\User;
use Illuminate\Support\Str;

class GoalImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('goals') as $record) {
            $this->importGoal($record['id'], $record['data']);
        }

        foreach ($this->reader->collectionGroup('tasks') as $record) {
            $this->withParentGoal('goal_tasks', $record, fn (string $goalId) => $this->importTask($goalId, $record['data'], $record['id']));
        }
        foreach ($this->reader->collectionGroup('updates') as $record) {
            $this->withParentGoal('goal_updates', $record, fn (string $goalId) => $this->importUpdate($goalId, $record['data'], $record['id']));
        }
        foreach ($this->reader->collectionGroup('comments') as $record) {
            if (! str_starts_with($record['path'], 'goals/')) {
                continue; // 'notes/{id}/comments' belongs to NotesImporter
            }
            $this->withParentGoal('goal_comments', $record, fn (string $goalId) => $this->importComment($goalId, $record['data'], $record['id']));
        }
        foreach ($this->reader->collectionGroup('merits') as $record) {
            $this->withParentGoal('goal_merits', $record, fn (string $goalId) => $this->importMerit($goalId, $record['data'], $record['id']));
            if (isset($record['data']['kind'])) {
                $this->report->skip('goal_merits.kind', $record['id'], "dropped historical 'kind' marker ({$record['data']['kind']}) — no column exists for it");
            }
        }
    }

    private function withParentGoal(string $collection, array $record, callable $handler): void
    {
        $segments = explode('/', $record['path']);
        $firestoreGoalId = $segments[1] ?? null;
        if ($firestoreGoalId === null) {
            $this->report->skip($collection, $record['id'], 'could not parse parent goal id from path '.$record['path']);

            return;
        }
        $handler($firestoreGoalId);
    }

    private function importGoal(string $firestoreId, array $data): void
    {
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        if ($userId === null) {
            $this->report->skip('goals', $firestoreId, 'no matching user for userId '.($data['userId'] ?? 'null'));

            return;
        }

        $goal = Goal::where('firestore_id', $firestoreId)->first() ?? new Goal(['id' => (string) Str::uuid()]);
        $goal->firestore_id = $firestoreId;
        $goal->user_id = $userId;
        $goal->company_id = $data['companyId'] ?? null;
        $goal->category = $data['category'] ?? 'PERSONAL';
        $goal->title = $data['title'] ?? '';
        $goal->description = $data['description'] ?? null;
        $goal->notes = $data['notes'] ?? null;
        $goal->status = $data['status'] ?? 'NOT_STARTED';
        $goal->goal_type = $data['goalType'] ?? 'MILESTONE';
        $goal->direction = $data['direction'] ?? 'GAIN';
        $goal->target_value = $data['targetValue'] ?? 0;
        $goal->current_value = $data['currentValue'] ?? 0;
        $goal->unit = $data['unit'] ?? null;
        $goal->target_period = $data['targetPeriod'] ?? 'NONE';
        $goal->start_date = $data['startDate'] ?? null;
        $goal->target_date = $data['targetDate'] ?? null;
        $goal->completed_at = $data['completedAt'] ?? null;
        $goal->progress = $data['progress'] ?? 0;
        $goal->save();

        $this->report->increment('goals', $goal->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importTask(string $firestoreGoalId, array $data, string $firestoreId): void
    {
        $goalId = Goal::where('firestore_id', $firestoreGoalId)->value('id');
        if ($goalId === null) {
            $this->report->skip('goal_tasks', $firestoreId, "no matching goal for {$firestoreGoalId}");

            return;
        }

        $task = GoalTask::where('firestore_id', $firestoreId)->first() ?? new GoalTask(['id' => (string) Str::uuid()]);
        $task->firestore_id = $firestoreId;
        $task->goal_id = $goalId;
        $task->title = $data['title'] ?? '';
        $task->status = $data['status'] ?? 'NOT_STARTED';
        $task->is_complete = $data['isComplete'] ?? (($data['status'] ?? null) === 'DONE');
        $task->due_date = $data['dueDate'] ?? null;
        $task->completed_at = $data['completedAt'] ?? null;
        $task->sort_order = $data['sortOrder'] ?? 0;
        $task->save();

        $this->report->increment('goal_tasks', $task->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importUpdate(string $firestoreGoalId, array $data, string $firestoreId): void
    {
        $goalId = Goal::where('firestore_id', $firestoreGoalId)->value('id');
        $authorId = User::where('firebase_uid', $data['authorId'] ?? null)->value('id');
        if ($goalId === null || $authorId === null) {
            $this->report->skip('goal_updates', $firestoreId, 'missing goal or author match');

            return;
        }

        $update = GoalUpdate::where('firestore_id', $firestoreId)->first() ?? new GoalUpdate(['id' => (string) Str::uuid()]);
        $update->firestore_id = $firestoreId;
        $update->goal_id = $goalId;
        $update->author_id = $authorId;
        $update->progress_from = $data['progressFrom'] ?? 0;
        $update->progress_to = $data['progressTo'] ?? 0;
        $update->status_from = $data['statusFrom'] ?? 'NOT_STARTED';
        $update->status_to = $data['statusTo'] ?? 'NOT_STARTED';
        $update->note = $data['note'] ?? null;
        $update->save();

        $this->report->increment('goal_updates', $update->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importComment(string $firestoreGoalId, array $data, string $firestoreId): void
    {
        $goalId = Goal::where('firestore_id', $firestoreGoalId)->value('id');
        $authorId = User::where('firebase_uid', $data['authorId'] ?? null)->value('id');
        if ($goalId === null || $authorId === null) {
            $this->report->skip('goal_comments', $firestoreId, 'missing goal or author match');

            return;
        }

        $comment = GoalComment::where('firestore_id', $firestoreId)->first() ?? new GoalComment(['id' => (string) Str::uuid()]);
        $comment->firestore_id = $firestoreId;
        $comment->goal_id = $goalId;
        $comment->author_id = $authorId;
        $comment->body = $data['body'] ?? '';
        $comment->is_private = $data['isPrivate'] ?? false;
        $comment->save();

        $this->report->increment('goal_comments', $comment->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importMerit(string $firestoreGoalId, array $data, string $firestoreId): void
    {
        $goal = Goal::where('firestore_id', $firestoreGoalId)->first();
        if ($goal === null) {
            $this->report->skip('goal_merits', $firestoreId, "no matching goal for {$firestoreGoalId}");

            return;
        }

        $merit = GoalMerit::where('firestore_id', $firestoreId)->first() ?? new GoalMerit(['id' => (string) Str::uuid()]);
        $merit->firestore_id = $firestoreId;
        $merit->goal_id = $goal->id;
        $merit->user_id = $goal->user_id;
        $merit->date = $data['date'] ?? null;
        $merit->amount = $data['amount'] ?? 0;
        $merit->save();

        $this->report->increment('goal_merits', $merit->wasRecentlyCreated ? 'created' : 'updated');
    }
}
