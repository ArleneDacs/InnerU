<?php
// backend/app/Services/FirestoreImport/UserImporter.php

namespace App\Services\FirestoreImport;

use App\Models\User;
use Illuminate\Support\Carbon;

class UserImporter
{
    public function __construct(
        private readonly SnapshotReader $reader,
        private readonly ImportReport $report,
    ) {
    }

    public function import(bool $dryRun): void
    {
        $firestoreUsers = $this->keyById($this->reader->collection('users'));
        $coaches = $this->keyById($this->reader->collection('coaches'));

        foreach ($this->reader->authUsers() as $authUser) {
            $uid = $authUser['localId'] ?? null;
            $email = $authUser['email'] ?? null;

            if (! is_string($uid) || $uid === '' || ! is_string($email) || $email === '') {
                $this->report->skip('users', (string) ($uid ?? 'unknown'), 'auth export record missing localId or email');

                continue;
            }

            $profile = $firestoreUsers[$uid] ?? [];
            $coach = $coaches[$uid] ?? null;

            $user = User::where('firebase_uid', $uid)->first()
                ?? User::where('email', $email)->first()
                ?? new User();
            $wasNew = ! $user->exists;

            $user->firebase_uid = $uid;
            $user->email = $email;
            $user->name = $coach['fullName'] ?? $profile['username'] ?? $profile['name'] ?? ($authUser['displayName'] ?? $email);
            $user->profile_pic = $profile['profilePic'] ?? ($authUser['photoUrl'] ?? $user->profile_pic);
            $user->active_company_id = $profile['activeCompanyId'] ?? $profile['companyId'] ?? $user->active_company_id;
            $user->company_id = $profile['companyId'] ?? $user->company_id;

            if ($wasNew) {
                $user->role = 'user';
            }

            if ($coach !== null) {
                $user->role = 'coach';
                $user->is_coach = true;
                if (isset($coach['bio'])) {
                    $user->bio = $coach['bio'];
                }
            }

            $user->email_verified_at = ($authUser['emailVerified'] ?? false) ? Carbon::now() : null;

            $appleProvider = collect($authUser['providerUserInfo'] ?? [])->firstWhere('providerId', 'apple.com');
            if ($appleProvider !== null && ! empty($appleProvider['rawId'])) {
                $user->apple_user_id = $appleProvider['rawId'];
            }

            $passwordProvider = collect($authUser['providerUserInfo'] ?? [])->firstWhere('providerId', 'password');
            if ($passwordProvider !== null && ! empty($authUser['passwordHash'])) {
                $user->legacy_password_hash = $authUser['passwordHash'];
                $user->legacy_password_salt = $authUser['salt'] ?? null;
            }

            $user->save();

            $this->report->increment('users', $wasNew ? 'created' : 'updated');
        }
    }

    /**
     * @param  array<int, array{id: string, data: array}>  $records
     * @return array<string, array<string, mixed>>
     */
    private function keyById(array $records): array
    {
        $byId = [];
        foreach ($records as $record) {
            $byId[$record['id']] = $record['data'];
        }

        return $byId;
    }
}
