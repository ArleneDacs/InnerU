<?php
// backend/app/Services/FirestoreImport/UserPointsImporter.php

namespace App\Services\FirestoreImport;

use App\Models\User;
use App\Models\UserPoint;

// Field mapping confirmed against the real production export (529
// documents): every field this class reads (userId, date, username,
// totalPoints, activityPoints, dailyTrackerScore, todoListScore,
// todoListScoreDailyContribution, todoListIncludedInTotal, userTotalScore,
// taskPoints, tasks, server, companyId, companyCode, companyName,
// activityCounts) is present in real data with no naming mismatches.
// activeCompanyId/activeCompanyCode/activeCompanyName also appear
// alongside companyId/companyCode/companyName (same pattern confirmed on
// the sibling `dailytracker` collection); reading only the plain company*
// fields loses no data.
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
        // 417 of 529 real documents have no userId field at all - but every
        // one of those document IDs matches the {firebaseUid}-{date}
        // pattern the old app wrote (e.g. "1FnRnpxZpMSblary0vBNXHuH1993-
        // 2026-07-20"), and 343 of the 417 extracted UIDs are real, existing
        // users. Recovering the UID from the doc ID (rather than treating a
        // missing field as "no match") is what actually restores this data
        // for those users. This also fixes a real bug: Eloquent's
        // where('firebase_uid', null) compiles to "firebase_uid IS NULL",
        // not "no match" - since firebase_uid is nullable (native
        // registrations since the 2026-07-21 cutover have no Firebase
        // account), the previous unguarded lookup could silently attach a
        // record to an arbitrary NULL-firebase_uid user instead of
        // recovering or skipping it.
        $firebaseUid = $data['userId'] ?? self::extractUidFromDocId($firestoreId);
        $date = $data['date'] ?? null;
        if ($firebaseUid === null || $date === null) {
            $this->report->skip('user_points', $firestoreId, 'missing matching user or date');

            return;
        }

        $userId = User::where('firebase_uid', $firebaseUid)->value('id');
        if ($userId === null) {
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
