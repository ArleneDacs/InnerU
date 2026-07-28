<?php
// backend/app/Services/FirestoreImport/DailyTrackerImporter.php

namespace App\Services\FirestoreImport;

use App\Models\DailyTracker;
use App\Models\User;

// Field mapping confirmed against the real production export (Task 4,
// scripts/firestore-export/snapshot/dailytracker.json, 634 documents):
// userId, username, call, steps, exercise, meditation, learning, addValue,
// todoList, date, lastUpdated (always a plain "YYYY-MM-DD" string, never a
// Firestore Timestamp - safe for the date:Y-m-d cast), stepCount, stepGoal,
// exerciseCount, exerciseMinutes, todoListCount, todoListScore,
// todoListScoreDailyContribution, todoListIncludedInTotal, userTotalScore,
// customDailyTasks, meditationMinutes, companyId, companyCode, companyName.
// callCount/learningCount/valueCount never appear in any real document -
// they default to 0 via the `?? 0` below, which is correct, not a bug.
// activeCompanyId/activeCompanyCode/activeCompanyName also appear on the 34
// documents that have company data at all, always identical in value to
// companyId/companyCode/companyName on the same document - reading the
// plain company* fields loses no data.
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
        // 97 of 634 real documents have no userId field at all - but every
        // one of those document IDs matches the {firebaseUid}-{date}
        // pattern the old app wrote (e.g. "0VjOoCOi7CcEydz07KmWoTiDoeX2-
        // 2026-07-21"), and 79 of the 97 extracted UIDs are real, existing
        // users. Recovering the UID from the doc ID (rather than skipping)
        // is what actually restores this data for those users, instead of
        // leaving it permanently missing. Guarding this explicitly also
        // matters for correctness: Eloquent's where('firebase_uid', null)
        // compiles to "firebase_uid IS NULL", not "no match" - since
        // firebase_uid is nullable (native registrations since the
        // 2026-07-21 cutover have no Firebase account), an unguarded lookup
        // with no fallback would silently attach the record to an arbitrary
        // NULL-firebase_uid user instead of skipping or recovering it.
        $firebaseUid = $data['userId'] ?? self::extractUidFromDocId($firestoreId);
        // Matches the old Dart code's _resolveTrackerDate fallback order
        // exactly: lastUpdated takes priority over date.
        $date = $data['lastUpdated'] ?? $data['date'] ?? null;
        if ($firebaseUid === null || $date === null) {
            $this->report->skip('daily_trackers', $firestoreId, 'missing matching user or date');

            return;
        }

        $userId = User::where('firebase_uid', $firebaseUid)->value('id');
        if ($userId === null) {
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

    // Firebase UIDs are always 28 alphanumeric characters, never containing
    // a hyphen (verified against all 188 real users in the production
    // export), so splitting on the trailing "-YYYY-MM-DD" is unambiguous.
    private static function extractUidFromDocId(string $firestoreId): ?string
    {
        return preg_match('/^(.+)-\d{4}-\d{2}-\d{2}$/', $firestoreId, $matches) === 1
            ? $matches[1]
            : null;
    }
}
