<?php
// backend/database/migrations/2026_07_25_000002_add_firestore_id_columns_for_migration_import.php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    private array $tables = [
        'goals', 'goal_tasks', 'goal_updates', 'goal_comments', 'goal_merits',
        'coach_groups', 'coach_requests', 'community_posts', 'note_comments',
        'fasting_history',
    ];

    public function up(): void
    {
        foreach ($this->tables as $table) {
            Schema::table($table, function (Blueprint $blueprint): void {
                $blueprint->string('firestore_id')->nullable()->unique()->after('id');
            });
        }
    }

    public function down(): void
    {
        foreach ($this->tables as $table) {
            Schema::table($table, function (Blueprint $blueprint): void {
                $blueprint->dropUnique(['firestore_id']);
                $blueprint->dropColumn('firestore_id');
            });
        }
    }
};
