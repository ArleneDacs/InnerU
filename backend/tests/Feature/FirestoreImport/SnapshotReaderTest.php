<?php
// backend/tests/Feature/FirestoreImport/SnapshotReaderTest.php

namespace Tests\Feature\FirestoreImport;

use App\Services\FirestoreImport\SnapshotReader;
use Illuminate\Support\Facades\File;
use Tests\TestCase;

class SnapshotReaderTest extends TestCase
{
    private string $dir;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dir = sys_get_temp_dir().'/snapshot-reader-test-'.uniqid();
        File::ensureDirectoryExists($this->dir);
    }

    protected function tearDown(): void
    {
        File::deleteDirectory($this->dir);
        parent::tearDown();
    }

    public function test_collection_reads_a_plain_collection_file(): void
    {
        File::put("{$this->dir}/users.json", json_encode([
            ['id' => 'uid1', 'data' => ['email' => 'a@example.com']],
        ]));

        $reader = new SnapshotReader($this->dir);

        $this->assertSame([
            ['id' => 'uid1', 'data' => ['email' => 'a@example.com']],
        ], $reader->collection('users'));
    }

    public function test_collection_returns_empty_array_when_file_is_missing(): void
    {
        $reader = new SnapshotReader($this->dir);

        $this->assertSame([], $reader->collection('does_not_exist'));
    }

    public function test_collection_group_reads_a_group_file_with_paths(): void
    {
        File::put("{$this->dir}/_group_tasks.json", json_encode([
            ['id' => 't1', 'path' => 'goals/g1/tasks/t1', 'data' => ['title' => 'Do it']],
        ]));

        $reader = new SnapshotReader($this->dir);

        $this->assertSame([
            ['id' => 't1', 'path' => 'goals/g1/tasks/t1', 'data' => ['title' => 'Do it']],
        ], $reader->collectionGroup('tasks'));
    }

    public function test_auth_users_reads_the_users_key_from_the_export_file(): void
    {
        File::put("{$this->dir}/auth-users.json", json_encode([
            'users' => [['localId' => 'uid1', 'email' => 'a@example.com']],
        ]));

        $reader = new SnapshotReader($this->dir);

        $this->assertSame([
            ['localId' => 'uid1', 'email' => 'a@example.com'],
        ], $reader->authUsers());
    }
}
