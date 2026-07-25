<?php
// backend/app/Services/FirestoreImport/WellnessImporter.php

namespace App\Services\FirestoreImport;

use App\Models\FastingHistory;
use App\Models\User;
use Illuminate\Support\Carbon;

class WellnessImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collectionGroup('wellness') as $record) {
            $this->importFastingDoc($record);
        }
        foreach ($this->reader->collectionGroup('history') as $record) {
            $this->importFastingHistoryEntry($record);
        }
    }

    private function importFastingDoc(array $record): void
    {
        $uid = explode('/', $record['path'])[1] ?? null;
        $user = $uid !== null ? User::where('firebase_uid', $uid)->first() : null;
        if ($user === null) {
            $this->report->skip('users.fasting', $record['id'], "no matching user for uid {$uid}");

            return;
        }

        $data = $record['data'];
        $user->fasting_target_hours = $data['targetHours'] ?? $user->fasting_target_hours;
        $user->fasting_start_at = $data['startTime'] ?? null;
        $user->fasting_end_at = $data['endTime'] ?? null;
        $user->fasting_last_completed_at = $data['lastCompletedAt'] ?? $user->fasting_last_completed_at;
        $user->save();

        $this->report->increment('users.fasting', 'updated');
    }

    private function importFastingHistoryEntry(array $record): void
    {
        $uid = explode('/', $record['path'])[1] ?? null;
        $userId = $uid !== null ? User::where('firebase_uid', $uid)->value('id') : null;
        if ($userId === null) {
            $this->report->skip('fasting_history', $record['id'], "no matching user for uid {$uid}");

            return;
        }

        $data = $record['data'];

        // fasting_history.finished_at is NOT NULL with no default (see
        // 2026_07_21_000013_create_fasting_history_table.php). Historical
        // Firestore `history` docs for an in-progress/abandoned fast that never
        // got a `_endFast` write can be missing `finishedAt` — saving that as
        // null would throw an uncaught NOT NULL constraint violation and, since
        // the import command wraps this importer's whole import() call in one
        // transaction, roll back the entire WellnessImporter batch. Skip
        // instead, matching GoalImporter's guard style for its own
        // required-field gaps.
        if (empty($data['finishedAt'])) {
            $this->report->skip('fasting_history', $record['id'], 'missing finishedAt');

            return;
        }

        $entry = FastingHistory::where('firestore_id', $record['id'])->first() ?? new FastingHistory();
        $entry->firestore_id = $record['id'];
        $entry->user_id = $userId;
        $entry->target_hours = $data['targetHours'] ?? 0;
        $entry->start_time = $data['startTime'] ?? null;
        $entry->planned_end_time = $data['plannedEndTime'] ?? null;
        $entry->finished_at = $data['finishedAt'];
        $entry->completed_hours = $data['completedHours'] ?? 0;
        $entry->completed_target = $data['completedTarget'] ?? false;

        if (! empty($data['createdAt'])) {
            $entry->timestamps = false;
            $entry->created_at = Carbon::parse($data['createdAt']);
            $entry->updated_at = $entry->created_at;
        }

        $entry->save();

        $this->report->increment('fasting_history', $entry->wasRecentlyCreated ? 'created' : 'updated');
    }
}
