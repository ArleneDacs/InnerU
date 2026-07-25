<?php
// backend/database/migrations/2026_07_25_000001_add_firestore_migration_columns_to_users_table.php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->string('firebase_uid')->nullable()->unique()->after('id');
            $table->text('legacy_password_hash')->nullable()->after('password');
            $table->string('legacy_password_salt')->nullable()->after('legacy_password_hash');
            $table->text('bio')->nullable()->after('profile_pic');
            $table->string('password')->nullable()->change();
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropUnique(['firebase_uid']);
            $table->dropColumn(['firebase_uid', 'legacy_password_hash', 'legacy_password_salt', 'bio']);
            $table->string('password')->nullable(false)->change();
        });
    }
};
