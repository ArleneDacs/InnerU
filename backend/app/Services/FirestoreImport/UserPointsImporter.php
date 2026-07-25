<?php
// backend/app/Services/FirestoreImport/UserPointsImporter.php

namespace App\Services\FirestoreImport;

use App\Models\User;
use App\Models\UserPoint;

// Field mapping below is an unverified hypothesis, not a confirmed fact: no
// Dart code in the live app reads Firestore `userpoints` fields back (the
// only real interaction is a blind `username` rewrite on account rename),
// so these names are inferred from the current Postgres schema and the
// current API's upsert payload shape. Confirm against a real exported
// snapshot (scripts/firestore-export/snapshot/userpoints.json) before
// trusting this mapping in production.
class UserPointsImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('userpoints') as $record) {
            $this->importRecord($record['id'], $record['data']);
        }
    }

    private function importRecord(string $firestoreId, array $data): void
    {
        $userId = User::where('firebase_uid', $data['userId'] ?? null)->value('id');
        $date = $data['date'] ?? null;
        if ($userId === null || $date === null) {
            $this->report->skip('user_points', $firestoreId, 'missing matching user or date');

            return;
        }

        $companyId = $data['companyId'] ?? null;
        $query = UserPoint::where('user_id', $userId)->where('date', $date);
        $query = $companyId === null ? $query->whereNull('company_id') : $query->where('company_id', $companyId);

        $record = $query->first() ?? new UserPoint();
        $record->user_id = $userId;
        $record->date = $date;
        $record->username = $data['username'] ?? '';
        $record->total_points = $data['totalPoints'] ?? 0;
        // activity_points/daily_tracker_score/todo_list_score/
        // todo_list_score_daily_contribution/user_total_score are all
        // integer columns, but real historical Firestore records can carry
        // fractional values (e.g. userTotalScore: 55.5) predating the
        // current API's integer validation (UserPointController.php:35) -
        // round rather than let a fractional value hit an integer column
        // and abort the whole import batch with a Postgres type error.
        $record->activity_points = (int) round($data['activityPoints'] ?? 0);
        $record->daily_tracker_score = (int) round($data['dailyTrackerScore'] ?? 0);
        $record->todo_list_score = (int) round($data['todoListScore'] ?? 0);
        $record->todo_list_score_daily_contribution = (int) round($data['todoListScoreDailyContribution'] ?? 0);
        $record->todo_list_included_in_total = $data['todoListIncludedInTotal'] ?? false;
        $record->user_total_score = (int) round($data['userTotalScore'] ?? 0);
        $record->task_points = $data['taskPoints'] ?? null;
        $record->tasks = $data['tasks'] ?? null;
        $record->server = $data['server'] ?? null;
        $record->company_id = $companyId;
        $record->company_code = $data['companyCode'] ?? null;
        $record->company_name = $data['companyName'] ?? null;
        $record->activity_counts = $data['activityCounts'] ?? null;
        $record->save();

        $this->report->increment('user_points', $record->wasRecentlyCreated ? 'created' : 'updated');
    }
}
