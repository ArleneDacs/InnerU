<?php
// backend/app/Services/FirestoreImport/DailyTrackerImporter.php

namespace App\Services\FirestoreImport;

use App\Models\DailyTracker;
use App\Models\User;

// Confirmed-real fields (from the removed pre-cutover Dart code in commit
// 8d8948b): userId, username, call, steps, exercise, meditation, learning,
// addValue, date/lastUpdated. Every other field below is inferred from the
// current Postgres schema and the current API's upsert payload shape
// (daily_tracker_api_service.dart) - confirm against a real exported
// snapshot (scripts/firestore-export/snapshot/dailytracker.json, produced
// by Task 4) before trusting this mapping in production.
class DailyTrackerImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('dailytracker') as $record) {
            $this->importRecord($record['id'], $record['data']);
        }
    }

    private function importRecord(string $firestoreId, array $data): void
    {
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        // Matches the old Dart code's _resolveTrackerDate fallback order
        // exactly: lastUpdated takes priority over date.
        $date = $data['lastUpdated'] ?? $data['date'] ?? null;
        if ($userId === null || $date === null) {
            $this->report->skip('daily_trackers', $firestoreId, 'missing matching user or date');

            return;
        }

        // daily_trackers has a live production writer (DailyTrackerController)
        // active since the 2026-07-21 cutover. Treat any existing row for
        // this user+date as authoritative and never overwrite it - this
        // importer only fills in historical gaps.
        if (DailyTracker::where('user_id', $userId)->where('date', $date)->exists()) {
            $this->report->skip('daily_trackers', $firestoreId, 'row already exists for this user and date');

            return;
        }

        $record = new DailyTracker();
        $record->user_id = $userId;
        $record->date = $date;
        $record->username = $data['username'] ?? '';
        $record->step_count = (int) round($data['stepCount'] ?? 0);
        $record->step_goal = (int) round($data['stepGoal'] ?? 5000);
        $record->meditation = (bool) ($data['meditation'] ?? false);
        $record->steps = (bool) ($data['steps'] ?? false);
        $record->call = (bool) ($data['call'] ?? false);
        $record->exercise = (bool) ($data['exercise'] ?? false);
        $record->learning = (bool) ($data['learning'] ?? false);
        $record->add_value = (bool) ($data['addValue'] ?? false);
        $record->todo_list = (bool) ($data['todoList'] ?? false);
        $record->call_count = (int) round($data['callCount'] ?? 0);
        $record->exercise_count = (int) round($data['exerciseCount'] ?? 0);
        $record->exercise_minutes = (int) round($data['exerciseMinutes'] ?? 0);
        $record->learning_count = (int) round($data['learningCount'] ?? 0);
        $record->value_count = (int) round($data['valueCount'] ?? 0);
        $record->todo_list_count = (int) round($data['todoListCount'] ?? 0);
        $record->todo_list_score = (int) round($data['todoListScore'] ?? 0);
        $record->todo_list_score_daily_contribution = (int) round($data['todoListScoreDailyContribution'] ?? 0);
        $record->todo_list_included_in_total = (bool) ($data['todoListIncludedInTotal'] ?? false);
        $record->user_total_score = (int) round($data['userTotalScore'] ?? 0);
        $record->custom_daily_tasks = $data['customDailyTasks'] ?? null;
        $record->meditation_minutes = (int) round($data['meditationMinutes'] ?? 0);
        $record->company_id = $data['companyId'] ?? null;
        $record->company_code = $data['companyCode'] ?? null;
        $record->company_name = $data['companyName'] ?? null;
        $record->save();

        $this->report->increment('daily_trackers', 'created');
    }
}
