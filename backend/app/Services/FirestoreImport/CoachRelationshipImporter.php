<?php
// backend/app/Services/FirestoreImport/CoachRelationshipImporter.php

namespace App\Services\FirestoreImport;

use App\Models\CoachGroup;
use App\Models\CoachMentee;
use App\Models\CoachRequest;
use App\Models\User;
use Illuminate\Support\Str;

class CoachRelationshipImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        foreach ($this->reader->collection('coach_groups') as $record) {
            $this->importGroup($record['id'], $record['data']);
        }
        foreach ($this->reader->collection('coach_requests') as $record) {
            $this->importRequest($record['id'], $record['data']);
        }

        $this->synthesizeBaseRelationships();
        $this->attachGroupMembership();
        $this->recomputeGroupCounts();
    }

    private function importGroup(string $firestoreId, array $data): void
    {
        $coachId = User::where('firebase_uid', $data['coachId'] ?? null)->value('id');
        if ($coachId === null) {
            $this->report->skip('coach_groups', $firestoreId, 'no matching coach for coachId '.($data['coachId'] ?? 'null'));

            return;
        }

        $group = CoachGroup::where('firestore_id', $firestoreId)->first() ?? new CoachGroup(['id' => (string) Str::uuid()]);
        $group->firestore_id = $firestoreId;
        $group->coach_id = (string) $coachId;
        $group->name = $data['name'] ?? '';
        $group->member_ids = $data['memberIds'] ?? [];
        $group->member_count = 0; // recomputed in recomputeGroupCounts() after synthesis
        $group->save();

        $this->report->increment('coach_groups', $group->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function importRequest(string $firestoreId, array $data): void
    {
        $coachId = User::where('firebase_uid', $data['coachId'] ?? null)->value('id');
        $menteeId = User::where('firebase_uid', $data['menteeId'] ?? null)->value('id');
        if ($coachId === null || $menteeId === null) {
            $this->report->skip('coach_requests', $firestoreId, 'missing coach or mentee match');

            return;
        }

        $request = CoachRequest::where('firestore_id', $firestoreId)->first() ?? new CoachRequest(['id' => (string) Str::uuid()]);
        $request->firestore_id = $firestoreId;
        $request->coach_id = (string) $coachId;
        $request->coach_name = $data['coachName'] ?? null;
        $request->coach_email = $data['coachEmail'] ?? null;
        $request->mentee_id = (string) $menteeId;
        $request->mentee_name = $data['menteeName'] ?? null;
        $request->mentee_email = $data['menteeEmail'] ?? null;
        $request->applicant_role = $data['applicantRole'] ?? null;
        $request->applicant_is_coach = $data['applicantIsCoach'] ?? false;
        $request->applying_as = $data['applyingAs'] ?? 'mentee';
        $request->status = $data['status'] ?? 'pending';
        $request->save();

        $this->report->increment('coach_requests', $request->wasRecentlyCreated ? 'created' : 'updated');
    }

    private function synthesizeBaseRelationships(): void
    {
        foreach ($this->reader->collection('users') as $record) {
            $data = $record['data'];
            $coachUids = $data['coachIds'] ?? (isset($data['coachId']) ? [$data['coachId']] : []);
            if (empty($coachUids)) {
                continue;
            }

            $mentee = User::where('firebase_uid', $record['id'])->first();
            if ($mentee === null) {
                continue;
            }

            foreach ($coachUids as $coachUid) {
                $coach = User::where('firebase_uid', $coachUid)->first();
                if ($coach === null) {
                    $this->report->skip('coach_mentees', $record['id'], "no matching coach for coachId {$coachUid}");

                    continue;
                }

                CoachMentee::query()->firstOrCreate(
                    ['coach_id' => (string) $coach->id, 'mentee_id' => (string) $mentee->id],
                    ['mentee_name' => $mentee->name, 'mentee_email' => $mentee->email],
                );
                $this->report->increment('coach_mentees', 'synced');
            }
        }
    }

    private function attachGroupMembership(): void
    {
        foreach ($this->reader->collection('coach_groups') as $record) {
            $data = $record['data'];
            $coachId = User::where('firebase_uid', $data['coachId'] ?? null)->value('id');
            $group = CoachGroup::where('firestore_id', $record['id'])->first();
            if ($coachId === null || $group === null) {
                continue;
            }

            foreach (($data['memberIds'] ?? []) as $memberUid) {
                $menteeId = User::where('firebase_uid', $memberUid)->value('id');
                if ($menteeId === null) {
                    continue;
                }

                CoachMentee::query()
                    ->where('coach_id', (string) $coachId)
                    ->where('mentee_id', (string) $menteeId)
                    ->update(['group_id' => $group->id, 'group_name' => $group->name]);
            }
        }
    }

    private function recomputeGroupCounts(): void
    {
        CoachGroup::query()->whereNotNull('firestore_id')->each(function (CoachGroup $group): void {
            $group->member_count = CoachMentee::where('group_id', $group->id)->count();
            $group->save();
        });
    }
}
