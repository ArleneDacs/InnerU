<?php
// backend/tests/Feature/FirestoreMigrationColumnsTest.php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class FirestoreMigrationColumnsTest extends TestCase
{
    use RefreshDatabase;

    public function test_users_table_has_migration_columns(): void
    {
        $this->assertTrue(Schema::hasColumns('users', [
            'firebase_uid',
            'legacy_password_hash',
            'legacy_password_salt',
            'bio',
        ]));
    }

    public function test_password_column_is_nullable(): void
    {
        $column = collect(Schema::getColumns('users'))->firstWhere('name', 'password');
        $this->assertNotNull($column);
        $this->assertTrue($column['nullable']);
    }

    public function test_firestore_id_columns_exist_on_migrated_tables(): void
    {
        $tables = [
            'goals', 'goal_tasks', 'goal_updates', 'goal_comments', 'goal_merits',
            'coach_groups', 'coach_requests', 'community_posts', 'note_comments',
            'fasting_history',
        ];

        foreach ($tables as $table) {
            $this->assertTrue(
                Schema::hasColumn($table, 'firestore_id'),
                "expected {$table} to have a firestore_id column"
            );
        }
    }
}
