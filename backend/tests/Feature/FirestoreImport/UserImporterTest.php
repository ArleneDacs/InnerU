<?php
// backend/tests/Feature/FirestoreImport/UserImporterTest.php

namespace Tests\Feature\FirestoreImport;

use App\Models\User;
use App\Services\FirestoreImport\ImportReport;
use App\Services\FirestoreImport\SnapshotReader;
use App\Services\FirestoreImport\UserImporter;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class UserImporterTest extends TestCase
{
    use RefreshDatabase;

    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/user-importer-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_imports_a_password_account_with_profile_and_hash(): void
    {
        File::put("{$this->dir}/users.json", json_encode([
            ['id' => 'uid-1', 'data' => ['username' => 'Jane', 'profilePic' => 'https://x/jane.png', 'activeCompanyId' => 'co-1']],
        ]));
        File::put("{$this->dir}/coaches.json", json_encode([]));
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [[
                'localId' => 'uid-1',
                'email' => 'jane@example.com',
                'emailVerified' => true,
                'passwordHash' => 'base64hash',
                'salt' => 'base64salt',
                'providerUserInfo' => [['providerId' => 'password']],
            ]],
        ]));

        $importer = new UserImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $user = User::where('firebase_uid', 'uid-1')->first();
        $this->assertNotNull($user);
        $this->assertSame('jane@example.com', $user->email);
        $this->assertSame('Jane', $user->name);
        $this->assertSame('https://x/jane.png', $user->profile_pic);
        $this->assertSame('co-1', $user->active_company_id);
        $this->assertNotNull($user->email_verified_at);
        $this->assertSame('base64hash', $user->legacy_password_hash);
        $this->assertSame('base64salt', $user->legacy_password_salt);
    }

    public function test_merges_a_coaches_doc_onto_the_matching_user(): void
    {
        File::put("{$this->dir}/users.json", json_encode([
            ['id' => 'uid-2', 'data' => ['username' => 'Coach Original']],
        ]));
        File::put("{$this->dir}/coaches.json", json_encode([
            ['id' => 'uid-2', 'data' => ['fullName' => 'Coach Full Name', 'bio' => 'Fitness coach for 10 years']],
        ]));
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-2', 'email' => 'coach@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));

        $importer = new UserImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $user = User::where('firebase_uid', 'uid-2')->first();
        $this->assertSame('Coach Full Name', $user->name);
        $this->assertSame('Fitness coach for 10 years', $user->bio);
        $this->assertTrue((bool) $user->is_coach);
        $this->assertSame('coach', $user->role);
    }

    public function test_apple_sign_in_provider_sets_apple_user_id_and_no_password_columns(): void
    {
        File::put("{$this->dir}/users.json", json_encode([]));
        File::put("{$this->dir}/coaches.json", json_encode([]));
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [[
                'localId' => 'uid-3',
                'email' => 'apple.user@example.com',
                'emailVerified' => true,
                'providerUserInfo' => [['providerId' => 'apple.com', 'rawId' => 'apple-sub-123']],
            ]],
        ]));

        $importer = new UserImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);

        $user = User::where('firebase_uid', 'uid-3')->first();
        $this->assertSame('apple-sub-123', $user->apple_user_id);
        $this->assertNull($user->legacy_password_hash);
    }

    public function test_rerunning_the_importer_updates_instead_of_duplicating(): void
    {
        File::put("{$this->dir}/users.json", json_encode([['id' => 'uid-4', 'data' => ['username' => 'Original']]]));
        File::put("{$this->dir}/coaches.json", json_encode([]));
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [['localId' => 'uid-4', 'email' => 'rerun@example.com', 'emailVerified' => true, 'providerUserInfo' => []]],
        ]));

        $importer = new UserImporter(new SnapshotReader($this->dir), new ImportReport());
        $importer->import(false);
        $importer->import(false);

        $this->assertSame(1, User::where('firebase_uid', 'uid-4')->count());
    }

    public function test_skips_an_auth_record_missing_a_local_id(): void
    {
        File::put("{$this->dir}/users.json", json_encode([]));
        File::put("{$this->dir}/coaches.json", json_encode([]));
        File::put("{$this->dir}/auth-users.json", json_encode(['users' => [['email' => 'no-uid@example.com']]]));

        $report = new ImportReport();
        $importer = new UserImporter(new SnapshotReader($this->dir), $report);
        $importer->import(false);

        $this->assertSame(0, User::count());
        $this->assertNotEmpty($report->skippedRecords());
    }
}
